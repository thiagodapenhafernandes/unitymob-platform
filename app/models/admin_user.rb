class AdminUser < ApplicationRecord
  include PhoneNormalizable

  ADMIN_THEME_MODES = %w[light dark].freeze
  ADMIN_THEME_MODE_DEFAULT = "light".freeze

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :timeoutable,
         :validatable, :omniauthable, omniauth_providers: [:facebook]

  has_one_attached :avatar

  belongs_to :tenant, optional: true
  belongs_to :profile, optional: true
  belongs_to :horizontal_profile, class_name: "Profile", optional: true
  belongs_to :manager, class_name: "AdminUser", optional: true # gestor de VENDA
  belongs_to :rentals_manager, class_name: "AdminUser", optional: true # gestor de LOCAÇÃO
  has_many :subordinates, ->(admin_user) { where(tenant_id: admin_user.tenant_id) }, class_name: "AdminUser", foreign_key: "manager_id"
  has_many :habitations
  has_many :habitation_exports, dependent: :destroy
  has_many :habitation_share_links, dependent: :destroy
  has_one :inbound_webhook_token, dependent: :destroy
  has_many :habitation_audit_logs
  has_many :access_audit_logs
  has_many :data_export_audit_logs
  has_many :lead_audit_logs
  has_many :trusted_devices, dependent: :destroy
  has_many :access_control_rules, dependent: :nullify
  has_many :created_whatsapp_campaigns, class_name: "WhatsappCampaign", foreign_key: "created_by_id", dependent: :restrict_with_error
  has_many :lead_labels, dependent: :destroy
  has_many :presentation_cards, dependent: :destroy

  # Field ops (check-in geolocalizado)
  belongs_to :default_store, class_name: "Store", optional: true
  has_many :store_shifts, dependent: :destroy
  has_many :store_shift_stores, -> { distinct }, through: :store_shifts, source: :store
  has_many :directed_stores, class_name: "Store", foreign_key: :director_admin_user_id, dependent: :nullify
  has_many :check_ins, dependent: :destroy
  has_one :active_check_in, -> { where(status: :active) }, class_name: "CheckIn"

  enum role: { editor: 0, admin: 1 }
  enum acting_type: { sales: 0, rentals: 1, both: 2 }

  # Admins do Sistema são operadores acima da conta: não aparecem nas listas/organograma/site da conta.
  scope :account_members, -> { where(super_admin: false) }
  scope :active,   -> { account_members.where(active: true) }
  scope :inactive, -> { account_members.where(active: false) }
  scope :displayed_on_site, -> { account_members.where(display_on_site: true) }

  def self.matching_access_profile(profile)
    return all if profile.blank?

    if profile.horizontal?
      where(horizontal_profile_id: profile.id)
    else
      where(profile_id: profile.id, horizontal_profile_id: nil)
    end
  end

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :admin_theme_mode, inclusion: { in: ADMIN_THEME_MODES }, if: -> { has_attribute?(:admin_theme_mode) }

  def effective_admin_theme_mode
    identity = login_identity
    return ADMIN_THEME_MODE_DEFAULT unless identity.has_attribute?(:admin_theme_mode)

    identity.admin_theme_mode.presence_in(ADMIN_THEME_MODES) || ADMIN_THEME_MODE_DEFAULT
  end

  def admin_dark_mode?
    effective_admin_theme_mode == "dark"
  end
  normalize_phone_fields :phone, :secondary_phone
  validates :tenant, presence: true, unless: :super_admin?
  validates :profile, presence: true, unless: :super_admin?
  validate :system_admin_outside_tenant
  validate :profile_tenant_consistency
  validate :manager_tenant_consistency
  before_validation :align_vertical_profile_with_horizontal
  before_validation :align_managers_with_acting, if: -> { has_attribute?(:rentals_manager_id) }
  validate :rentals_manager_tenant_consistency, if: -> { has_attribute?(:rentals_manager_id) }
  validate :horizontal_profile_consistency
  validate :legacy_admin_role_consistency
  validate :tenant_must_keep_an_active_owner

  before_validation :clear_account_context_for_system_admin
  before_validation :assign_default_tenant
  before_validation :assign_default_vertical_profile
  before_destroy :ensure_not_last_active_tenant_owner
  
  # ===== Multi-conta (usuário espelho) =====
  # Espelho = linha comum de admin_users em OUTRA conta, linkada ao usuário
  # primário (quem faz login). Guards para funcionar pré-migration 20260705000006.
  belongs_to :primary_admin_user, class_name: "AdminUser", optional: true
  has_many :mirror_users, class_name: "AdminUser", foreign_key: :primary_admin_user_id, dependent: :nullify
  has_many :account_memberships, foreign_key: :primary_admin_user_id, dependent: :destroy

  MIRROR_EMAIL_DOMAIN = "espelho.unitymob.internal".freeze

  validate :mirror_consistency, if: -> { has_attribute?(:primary_admin_user_id) && primary_admin_user_id.present? }

  def mirror?
    has_attribute?(:primary_admin_user_id) && primary_admin_user_id.present?
  end

  # Identidade que faz login (o próprio usuário, ou o primário quando espelho).
  def login_identity
    mirror? ? (primary_admin_user || self) : self
  end

  # E-mail humano para notificações/telas: espelho guarda o real em contact_email.
  def notification_email
    (contact_email.presence if has_attribute?(:contact_email)) || email
  end

  def self.mirror_email_for(primary, tenant)
    "m#{primary.id}.t#{tenant.id}@#{MIRROR_EMAIL_DOMAIN}"
  end

  # Contas alternáveis: a natal do primário + memberships ativas (com espelho).
  def switchable_accounts
    identity = login_identity
    accounts = [{ tenant: identity.tenant, admin_user: identity, primary: true }]
    if identity.has_attribute?(:primary_admin_user_id)
      identity.mirror_users.where(active: true).includes(:tenant).find_each do |mirror|
        accounts << { tenant: mirror.tenant, admin_user: mirror, primary: false }
      end
    end
    accounts.compact.select { |entry| entry[:tenant].present? }
  end

  # ===== 2FA TOTP (Google Authenticator) =====
  # Guards has_attribute?/column check: código funciona ANTES da migration
  # 20260705000003 (fluxo antigo de login, 2FA "desligado").
  encrypts :otp_secret if (column_names.include?("otp_secret") rescue false)

  # LGPD: documentos do corretor cifrados at-rest (sem busca SQL por eles).
  if (column_names.include?("cpf_cnpj") rescue false)
    encrypts :cpf_cnpj
    encrypts :rg_ie
  end

  def otp_enabled?
    has_attribute?(:otp_enabled_at) && otp_enabled_at.present?
  end

  # A conta pode exigir 2FA de todos (tenants.require_two_factor).
  def two_factor_required?
    tenant.present? && tenant.respond_to?(:require_two_factor) && tenant.require_two_factor?
  end

  # Valida um código TOTP com tolerância de relógio (30s para trás) e
  # anti-replay: o mesmo timestep não autentica duas vezes.
  def verify_totp!(code)
    return false unless otp_enabled? && otp_secret.present?

    timestep = ROTP::TOTP.new(otp_secret, issuer: otp_issuer)
                         .verify(code.to_s.gsub(/\s+/, ""), drift_behind: 30, after: otp_consumed_timestep)
    return false unless timestep

    update_column(:otp_consumed_timestep, timestep)
    true
  end

  # Backup codes: comparação BCrypt, uso único (digest removido ao usar).
  def verify_backup_code!(code)
    return false unless otp_enabled?

    normalized = code.to_s.gsub(/\s+/, "")
    digests = Array(otp_backup_codes)
    used = digests.find do |digest|
      BCrypt::Password.new(digest) == normalized
    rescue BCrypt::Errors::InvalidHash
      false
    end
    return false unless used

    update_column(:otp_backup_codes, digests - [used])
    true
  end

  # Gera 10 códigos, guarda só os digests e retorna os textos UMA vez.
  def generate_backup_codes!
    codes = Array.new(10) { SecureRandom.alphanumeric(10) }
    update_column(:otp_backup_codes, codes.map { |c| BCrypt::Password.create(c).to_s })
    codes
  end

  def otp_provisioning_uri
    return nil if otp_secret.blank?

    ROTP::TOTP.new(otp_secret, issuer: otp_issuer).provisioning_uri(email)
  end

  def otp_issuer
    tenant&.name.presence || "CRM"
  end

  # ===== Expiração de sessão por conta (Devise timeoutable/rememberable) =====
  # Config vem do tenant (tela Segurança de Acesso); guards p/ pré-migration
  # 20260707000002. Espelhos multi-conta pertencem ao tenant convidado, então a
  # política daquela conta se aplica naturalmente.
  def timeout_in
    return nil unless tenant&.has_attribute?(:session_timeout_enabled) && tenant.session_timeout_enabled?

    days = tenant.session_timeout_days.to_i
    days.positive? ? days.days : nil
  end

  # Cap por conta na validade do "lembrar deste dispositivo": limita o cookie...
  def remember_expires_at
    cap = session_remember_cap
    cap ? [super, cap.from_now].min : super
  end

  # ...e invalida no servidor tokens gerados antes da janela da conta.
  def remember_me?(token, generated_at)
    return false unless super

    cap = session_remember_cap
    return true unless cap

    generated_at = time_from_json(generated_at) if generated_at.is_a?(String)
    generated_at.is_a?(Time) && generated_at > cap.ago
  end

  # Admin do Sistema opera a plataforma e fica fora dos tenants. Tenant Owner é o
  # topo operacional dentro da conta. Não misture os dois conceitos em `admin?`.
  def system_admin?
    super_admin?
  end

  def admin?
    tenant_owner?
  end

  def can_manage_profiles?
    system_admin? || tenant_owner?
  end

  def profile
    return nil if system_admin?

    tenant_guarded(super)
  end

  # Perfil EXIBIDO em listas/telas: o que foi setado no cadastro — a função
  # operacional quando houver, senão o perfil de hierarquia.
  def access_profile
    horizontal_profile || (system_admin? ? nil : profile)
  end

  def access_profile_name
    access_profile&.name.presence || role&.humanize
  end

  def manager_display_name
    sales_manager = manager if sales? || both?
    rental_manager = rentals_manager if has_attribute?(:rentals_manager_id) && (rentals? || both?)

    return "Venda: #{sales_manager.name} · Locação: #{rental_manager.name}" if sales_manager.present? && rental_manager.present? && sales_manager.id != rental_manager.id

    (sales_manager || rental_manager)&.name
  end

  def horizontal_profile
    return nil if system_admin?

    tenant_guarded(super)
  end

  def manager
    return nil if system_admin?

    tenant_guarded(super)
  end

  def can?(action, resource)
    return true if admin?
    return false unless vertical_profile

    vertical_profile.can?(action, resource) || horizontal_profile&.can?(action, resource) == true
  end

  # "own" — só os próprios / "team" — próprios + subárvore de gestão / "all" — tudo
  def scope_for(resource)
    return "all" if admin?
    vertical_scope = vertical_profile&.scope_for(resource) || "own"
    horizontal_scope = horizontal_profile&.configured_scope_for(resource)
    Profile.restricted_scope(vertical_scope, horizontal_scope)
  end

  def can_manage_user?(other_user)
    return true if system_admin?
    return false unless other_user&.tenant_id == tenant_id
    return false if other_user.system_admin?
    return true if tenant_owner?
    return false unless can?(:manage, :corretores)
    return false if other_user.id == id
    return false unless other_user.id.in?(descendant_ids)

    vertical_above?(other_user)
  end

  def can_assign_vertical_profile?(target_profile)
    return true if system_admin?
    return false unless target_profile&.tenant_id == tenant_id
    return false unless target_profile.vertical?
    return true if tenant_owner?
    return false unless can?(:manage, :corretores)
    return false if vertical_profile.blank?

    target_profile.position.to_i > vertical_profile.position.to_i
  end

  def can_assign_horizontal_profile?(target_profile)
    return true if target_profile.blank?
    return true if system_admin?
    return false unless target_profile.tenant_id == tenant_id
    return false unless target_profile.horizontal?
    return true if tenant_owner?
    return false unless can?(:manage, :corretores)

    can_assign_vertical_profile?(target_profile.root_vertical_profile)
  end

  def owns_all?(resource)
    scope_for(resource) == "all"
  end

  # Perfil enxerga a equipe (subárvore de gestão) para o recurso?
  def can_view_team?(resource)
    scope_for(resource) == "team"
  end

  # IDs do próprio usuário + toda a subárvore de gestão (equipe), usado no escopo "team".
  def team_scope_ids
    @team_scope_ids ||= [id] + descendant_ids
  end

  def subordinate_ids
    @subordinate_ids ||= [id] + subordinates.pluck(:id)
  end

  # Todos os descendentes (recursivo) na árvore de gestão — não inclui o próprio.
  def descendant_ids
    rentals_join = has_attribute?(:rentals_manager_id)
    manager_match = rentals_join ? "(manager_id = %{id} OR rentals_manager_id = %{id})" : "manager_id = %{id}"
    child_match = rentals_join ? "(a.manager_id = s.id OR a.rentals_manager_id = s.id)" : "a.manager_id = s.id"
    # UNION (sem ALL): deduplica o conjunto recursivo — termina mesmo com
    # vínculos duplicados (venda = locação) ou laços entre as duas árvores.
    # Com UNION ALL a recursão re-expandia caminhos indefinidamente e a query
    # travava o pool de conexões inteiro.
    sql = <<~SQL
      WITH RECURSIVE subtree AS (
        SELECT id, 1 AS depth FROM admin_users WHERE #{format(manager_match, id: id.to_i)} AND tenant_id = #{tenant_id.to_i}
        UNION
        SELECT a.id, s.depth + 1 FROM admin_users a JOIN subtree s ON #{child_match}
        WHERE a.tenant_id = #{tenant_id.to_i} AND s.depth < 20
      )
      SELECT DISTINCT id FROM subtree
    SQL
    self.class.connection.select_values(sql).map(&:to_i)
  end

  # Conta descendentes por nível imediato (diretos) e total.
  def direct_subordinates_count
    subordinates.size
  end

  def total_descendants_count
    descendant_ids.size
  end

  def vertical_profile
    profile
  end

  def tenant_owner?
    vertical_profile&.tenant_owner? || false
  end

  def vertical_above?(other_user)
    return false unless same_account_user?(other_user)
    return false if vertical_profile.blank? || other_user.vertical_profile.blank?

    vertical_profile.position.to_i < other_user.vertical_profile.position.to_i
  end

  def same_vertical_level?(other_user)
    return false unless same_account_user?(other_user)
    return false if vertical_profile.blank? || other_user.vertical_profile.blank?

    vertical_profile.position.to_i == other_user.vertical_profile.position.to_i
  end

  def manager_candidate_for?(user)
    return false unless same_account_user?(user)
    return false if user.id.present? && id == user.id
    return false if user.id.present? && user.descendant_ids.include?(id)
    return true if user.profile.blank? || profile.blank?

    vertical_above?(user)
  end

  private

  # Janela efetiva do lembrar-me: o menor entre a validade configurada e o
  # timeout de inatividade — o login sempre lembra o dispositivo (sessions
  # controller seta remember_me = true), então sem esse cap o cookie anularia
  # o timeout do Devise (o hook de timeoutable ignora quem tem remember válido).
  def session_remember_cap
    return nil if tenant.blank?

    caps = []
    if tenant.has_attribute?(:session_remember_days) && tenant.session_remember_days.to_i.positive?
      caps << tenant.session_remember_days.to_i.days
    end
    caps << timeout_in if timeout_in
    caps.min
  end

  def same_account_user?(other_user)
    tenant_id.present? && other_user.present? && other_user.tenant_id == tenant_id
  end

  def clear_account_context_for_system_admin
    return unless super_admin?

    self.tenant = nil
    self.profile = nil
    self.horizontal_profile = nil
    self.manager = nil
  end

  def assign_default_tenant
    return if super_admin?

    self.tenant ||= Current.tenant
  end

  def assign_default_vertical_profile
    return if super_admin? || profile.present? || tenant.blank?

    self.profile =
      if role == "admin"
        tenant.profiles.vertical.find_by(key: "tenant_owner")
      end

    self.profile ||= tenant.profiles.vertical.find_by(key: "agent")
    self.profile ||= tenant.profiles.vertical.order(position: :desc, id: :desc).first
  end

  def profile_tenant_consistency
    assigned_profile = raw_profile
    return if assigned_profile.blank?

    errors.add(:profile, "deve ser um perfil vertical") unless assigned_profile.vertical?
    errors.add(:profile, "deve pertencer ao mesmo Tenant") if tenant_id.present? && assigned_profile.tenant_id != tenant_id
  end

  def system_admin_outside_tenant
    return unless super_admin?

    errors.add(:tenant, "deve ficar vazio para Admin do Sistema") if tenant_id.present?
    errors.add(:profile, "deve ficar vazio para Admin do Sistema") if profile_id.present?
    errors.add(:horizontal_profile, "deve ficar vazio para Admin do Sistema") if horizontal_profile_id.present?
    errors.add(:manager, "deve ficar vazio para Admin do Sistema") if manager_id.present?
    errors.add(:rentals_manager, "deve ficar vazio para Admin do Sistema") if has_attribute?(:rentals_manager_id) && rentals_manager_id.present?
  end

  def manager_tenant_consistency
    assigned_manager = raw_manager
    return if assigned_manager.blank? || tenant_id.blank?

    errors.add(:manager, "deve pertencer ao mesmo Tenant") if assigned_manager.tenant_id != tenant_id
    return if assigned_manager.tenant_id != tenant_id || profile.blank? || assigned_manager.profile.blank?

    unless assigned_manager.vertical_above?(self)
      errors.add(:manager, "deve estar acima do usuário na hierarquia vertical")
    end
  end

  def mirror_consistency
    if primary_admin_user_id == id
      errors.add(:primary_admin_user_id, "não pode apontar para si mesmo")
    end
    if primary_admin_user&.mirror?
      errors.add(:primary_admin_user_id, "deve apontar para o usuário primário, não para outro espelho")
    end
    if primary_admin_user && primary_admin_user.tenant_id == tenant_id
      errors.add(:primary_admin_user_id, "espelho não pode ser da mesma conta do primário")
    end
    errors.add(:base, "Admin do Sistema não pode ser espelho") if super_admin?
  end

  def rentals_manager_tenant_consistency
    assigned = rentals_manager
    return if assigned.blank? || tenant_id.blank?

    errors.add(:rentals_manager, "deve pertencer ao mesmo Tenant") if assigned.tenant_id != tenant_id
    return if assigned.tenant_id != tenant_id || profile.blank? || assigned.profile.blank?

    unless assigned.vertical_above?(self)
      errors.add(:rentals_manager, "deve estar acima do usuário na hierarquia vertical")
    end

    # anti-ciclo entre as DUAS árvores (o trigger do banco cobre só manager_id)
    if persisted? && (assigned.id == id || descendant_ids.include?(assigned.id))
      errors.add(:rentals_manager, "criaria um ciclo na hierarquia")
    end
  end

  # Coerência gestor × área de atuação: cada área usa o campo próprio.
  def align_managers_with_acting
    return if respond_to?(:rentals_manager_id) == false

    case acting_type.to_s
    when "sales" then self.rentals_manager_id = nil
    when "rentals" then self.manager_id = nil
    end
  end

  # A âncora horizontal→vertical é definida NA CRIAÇÃO DO PERFIL: aqui o
  # vertical é DERIVADO dela (nunca validado contra escolha manual). Âncoras
  # podem estar encadeadas (horizontal→horizontal→vertical): sobe até o vertical.
  def align_vertical_profile_with_horizontal
    assigned = raw_horizontal_profile
    return if assigned.blank?

    root = assigned.root_vertical_profile
    self.profile_id = root.id if root
  end

  def horizontal_profile_consistency
    assigned_horizontal_profile = raw_horizontal_profile
    return if assigned_horizontal_profile.blank?

    errors.add(:horizontal_profile, "deve ser um perfil horizontal") unless assigned_horizontal_profile.horizontal?
    errors.add(:horizontal_profile, "deve pertencer ao mesmo Tenant") if tenant_id.present? && assigned_horizontal_profile.tenant_id != tenant_id
  end

  def legacy_admin_role_consistency
    return if super_admin? || role != "admin" || profile.blank?

    errors.add(:role, "admin exige perfil vertical Tenant Owner") unless profile.tenant_owner?
  end

  def tenant_must_keep_an_active_owner
    return unless persisted_tenant_owner_without_replacement?

    errors.add(:base, "Tenant precisa manter ao menos um Tenant Owner ativo")
  end

  def persisted_tenant_owner_without_replacement?
    return false unless persisted?

    previous_tenant_id = tenant_id_was.presence || tenant_id
    return false if previous_tenant_id.blank?

    was_owner = profile_id_was.present? && Profile.where(id: profile_id_was, tenant_id: previous_tenant_id, key: "tenant_owner").exists?
    return false unless was_owner
    return false if !super_admin? && active? && tenant_id == previous_tenant_id && profile&.tenant_owner?

    !tenant_has_other_active_owner?(tenant_id: previous_tenant_id)
  end

  def ensure_not_last_active_tenant_owner
    return unless tenant_owner? && active?
    return if tenant_has_other_active_owner?

    errors.add(:base, "Tenant precisa manter ao menos um Tenant Owner ativo")
    throw(:abort)
  end

  def tenant_has_other_active_owner?(tenant_id: self.tenant_id)
    return false if tenant_id.blank?

    self.class
      .joins(:profile)
      .where(tenant_id: tenant_id, active: true, super_admin: false, profiles: { key: "tenant_owner" })
      .where.not(id: id)
      .exists?
  end

  def tenant_guarded(record)
    return record if record.blank? || tenant_id.blank?
    return record if record.tenant_id == tenant_id

    nil
  end

  def raw_profile
    Profile.unscoped.find_by(id: profile_id)
  end

  def raw_horizontal_profile
    Profile.unscoped.find_by(id: horizontal_profile_id)
  end

  def raw_manager
    self.class.unscoped.find_by(id: manager_id)
  end

end
