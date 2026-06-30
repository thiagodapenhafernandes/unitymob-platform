class AdminUser < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:facebook]

  has_one_attached :avatar

  belongs_to :tenant, optional: true
  belongs_to :profile, optional: true
  belongs_to :horizontal_profile, class_name: "Profile", optional: true
  belongs_to :manager, class_name: "AdminUser", optional: true
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

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :tenant, presence: true, unless: :super_admin?
  validates :profile, presence: true, unless: :super_admin?
  validate :system_admin_outside_tenant
  validate :profile_tenant_consistency
  validate :manager_tenant_consistency
  validate :horizontal_profile_consistency
  validate :legacy_admin_role_consistency
  validate :tenant_must_keep_an_active_owner

  before_validation :clear_account_context_for_system_admin
  before_validation :assign_default_tenant
  before_validation :assign_default_vertical_profile
  before_destroy :ensure_not_last_active_tenant_owner
  
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

    can_assign_vertical_profile?(target_profile.vertical_profile)
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
    sql = <<~SQL
      WITH RECURSIVE subtree AS (
        SELECT id FROM admin_users WHERE manager_id = #{id.to_i} AND tenant_id = #{tenant_id.to_i}
        UNION ALL
        SELECT a.id FROM admin_users a JOIN subtree s ON a.manager_id = s.id WHERE a.tenant_id = #{tenant_id.to_i}
      )
      SELECT id FROM subtree
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

  def horizontal_profile_consistency
    assigned_horizontal_profile = raw_horizontal_profile
    return if assigned_horizontal_profile.blank?

    errors.add(:horizontal_profile, "deve ser um perfil horizontal") unless assigned_horizontal_profile.horizontal?
    errors.add(:horizontal_profile, "deve pertencer ao mesmo Tenant") if tenant_id.present? && assigned_horizontal_profile.tenant_id != tenant_id
    if profile_id.present? && assigned_horizontal_profile.vertical_profile_id.present? && assigned_horizontal_profile.vertical_profile_id != profile_id
      errors.add(:horizontal_profile, "deve estar anexado ao perfil vertical do usuário")
    end
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
