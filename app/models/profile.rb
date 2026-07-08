class Profile < ApplicationRecord
  AXES = {
    vertical: "vertical",
    horizontal: "horizontal"
  }.freeze

  SCOPE_RANKS = {
    "own" => 0,
    "team" => 1,
    "all" => 2
  }.freeze

  belongs_to :tenant
  belongs_to :vertical_profile, class_name: "Profile", optional: true
  has_many :horizontal_profiles, ->(profile) { where(tenant_id: profile.tenant_id) }, class_name: "Profile", foreign_key: :vertical_profile_id, dependent: :restrict_with_error
  has_many :admin_users, ->(profile) { where(tenant_id: profile.tenant_id) }
  has_many :horizontal_admin_users, ->(profile) { where(tenant_id: profile.tenant_id) }, class_name: "AdminUser", foreign_key: :horizontal_profile_id, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: [:tenant_id, :axis, :vertical_profile_id] }
  validates :key, uniqueness: { scope: :tenant_id }, allow_nil: true
  validates :axis, inclusion: { in: AXES.values }
  validates :position, numericality: { only_integer: true }, allow_nil: true
  validate :vertical_profile_rules
  validate :locked_profile_invariants
  validate :builtin_profile_axis_invariants
  validate :system_vertical_key_uniqueness
  validate :vertical_position_uniqueness

  # `key` é o identificador ESTÁVEL do papel do sistema, usado pelo código no lugar do
  # nome (que é só rótulo livre e pode ser renomeado sem quebrar comportamento).
  ROLE_KEY_NAMES = {
    "tenant_owner"   => "Tenant Owner",
    "gerente"        => "Gerente",
    "administrativo" => "Administrativo",
    "agent"          => "Agent"
  }.freeze

  INTERNAL_MANAGEMENT_PROFILE_NAME = "Gestão Interna".freeze
  INTERNAL_MANAGEMENT_PROFILE_POSITION = 100

  ROLE_NAME_KEYS = {
    "Tenant Owner" => "tenant_owner",
    "Administrador" => "tenant_owner",
    "Gerente" => "gerente",
    "Administrativo" => "administrativo",
    "Agent" => "agent",
    "Corretor" => "agent"
  }.freeze

  before_validation :assign_default_tenant
  before_validation :assign_role_key
  before_validation :normalize_axis
  before_validation :normalize_vertical_position

  # Catálogo de recursos configuráveis via UI em /admin/profiles.
  # Cada entrada define: label humano, ícone, ações disponíveis e se suporta scope own/all.
  RESOURCES = [
    { key: "imoveis",            label: "Imóveis",                icon: "bi-houses",           actions: %w[view media manage], scopeable: true,  description: "Catálogo de imóveis, mídia e uploads" },
    { key: "leads",              label: "Leads",                  icon: "bi-megaphone",        actions: %w[view manage],       scopeable: true,  description: "Atendimento e gestão de leads" },
    { key: "comercial",          label: "Comercial",              icon: "bi-briefcase",        actions: %w[view manage],       scopeable: true,  description: "Tarefas, agenda e propostas comerciais" },
    { key: "whatsapp_inbox",     label: "Atendimento WhatsApp",   icon: "bi-whatsapp",         actions: %w[view manage],       scopeable: true,  description: "Central de atendimento (inbox) do WhatsApp" },
    { key: "whatsapp_campaigns", label: "Disparos WhatsApp",      icon: "bi-send",             actions: %w[view manage],       scopeable: true,  description: "Campanhas e disparos em massa pelo WhatsApp" },
    { key: "automacoes",         label: "Automação",              icon: "bi-lightning-charge", actions: %w[manage],            scopeable: false, description: "Regras de automação e nutrição de leads" },
    { key: "captacoes",          label: "Captações",              icon: "bi-journal-plus",     actions: %w[view manage review publish], scopeable: true, description: "Intake de imóveis em campo" },
    { key: "captacao_dashboard", label: "Dashboard Captação",     icon: "bi-bullseye",         actions: %w[view],              scopeable: false, description: "Métricas e gauges de captação" },
    { key: "agenda_fotografia",  label: "Agenda de fotografia",   icon: "bi-camera",           actions: %w[view manage],       scopeable: false, description: "Agenda e imóveis pendentes de fotografia" },
    { key: "distribution_rules", label: "Regras de distribuição", icon: "bi-diagram-3",        actions: %w[view manage],       scopeable: false, description: "Distribuição automática de leads" },
    { key: "lojas",              label: "Lojas",                  icon: "bi-shop",             actions: %w[view manage],       scopeable: false, description: "Cadastro de lojas físicas" },
    { key: "field_checkins",     label: "Check-ins em Campo",     icon: "bi-geo-fill",         actions: %w[view manage],       scopeable: false, description: "Monitorar check-ins de corretores em plantão" },
    { key: "field_manual",       label: "Pedidos manuais",        icon: "bi-hand-index-thumb", actions: %w[view manage],       scopeable: false, description: "Aprovar check-ins manuais quando GPS falha" },
    { key: "field_audit",        label: "Auditoria de Campo",     icon: "bi-shield-lock",      actions: %w[view],              scopeable: true,  description: "Trilha append-only de eventos de presença" },
    { key: "access_audit",       label: "Auditoria de Acessos",   icon: "bi-person-lock",      actions: %w[view],              scopeable: true,  description: "Logins, logouts, IPs, aparelhos e acessos negados" },
    { key: "data_export_audit",  label: "Auditoria de Exportações", icon: "bi-file-earmark-arrow-down", actions: %w[view],     scopeable: true,  description: "Exportações CSV, relatórios e impressões de dados" },
    { key: "access_security",    label: "Segurança de Acesso",    icon: "bi-fingerprint",      actions: %w[manage],            scopeable: true,  description: "Regras de IP permitido, IP bloqueado e aparelhos confiáveis" },
    { key: "field_settings",     label: "Configurações de Campo", icon: "bi-toggles2",         actions: %w[manage],            scopeable: false, description: "Liga/desliga módulo de presença em campo" },
    { key: "proprietarios",      label: "Proprietários",          icon: "bi-person-vcard",     actions: %w[view manage],       scopeable: false, description: "Cadastro de proprietários" },
    { key: "corretores",         label: "Corretores",             icon: "bi-people",           actions: %w[view manage sync], scopeable: false, description: "Gerenciar AdminUsers" },
    { key: "metas_captacao",     label: "Metas de captação",      icon: "bi-bullseye",         actions: %w[view manage],       scopeable: false, description: "Metas anuais por tipo" },
    { key: "catalogos",          label: "Catálogos dinâmicos",    icon: "bi-tags",             actions: %w[view manage],       scopeable: false, description: "Opções de atributos" },
    { key: "marketing",          label: "Marketing e conteúdo",   icon: "bi-megaphone-fill",   actions: %w[manage],            scopeable: false, description: "Banners, landing, SEO, home, rodapé" },
    { key: "integracoes",        label: "Integrações",            icon: "bi-plug",             actions: %w[manage],            scopeable: false, description: "Meta, DWV, Loft, Portais, Webhooks" },
    { key: "inbound_webhooks",   label: "Webhook de entrada",     icon: "bi-box-arrow-in-down", actions: %w[manage],           scopeable: false, description: "Token pessoal para receber leads por webhook (independente das integrações da conta)" },
    { key: "dashboard",          label: "Dashboard principal",    icon: "bi-speedometer2",     actions: %w[view],              scopeable: false, description: "Página inicial do admin" }
  ].freeze

  # Label human-friendly das ações
  ACTION_LABELS = {
    "view"    => "Visualizar",
    "media"   => "Mídia",
    "manage"  => "Gerenciar",
    "review"  => "Aprovar",
    "publish" => "Publicar",
    "sync"    => "Sincronizar"
  }.freeze

  PROFILE_PRESETS = {
    "Administrador" => {
      "admin" => true
    },
    "Corretor" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "manage" => false, "scope" => "own" },
      "leads" => { "view" => true, "manage" => true, "scope" => "own" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "own" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" },
      "captacoes" => { "view" => true, "manage" => true, "review" => false, "publish" => true, "scope" => "own" }
    },
    "Administrativo" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "manage" => true, "scope" => "all" },
      "leads" => { "view" => true, "manage" => true, "scope" => "all" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "all" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "all" },
      "whatsapp_campaigns" => { "view" => true, "manage" => true, "scope" => "all" },
      "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "all" },
      "captacao_dashboard" => { "view" => true },
      "agenda_fotografia" => { "view" => true, "manage" => true },
      "marketing" => { "manage" => true },
      "automacoes" => { "manage" => true }
    },
    "Gerente" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "manage" => true, "scope" => "team" },
      "leads" => { "view" => true, "manage" => true, "scope" => "team" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "team" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "team" },
      "whatsapp_campaigns" => { "view" => true, "manage" => true, "scope" => "team" },
      "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "team" },
      "captacao_dashboard" => { "view" => true }
    }
  }.freeze

  scope :vertical, -> { where(axis: AXES[:vertical]) }
  scope :horizontal, -> { where(axis: AXES[:horizontal]) }
  scope :ordered_vertical, -> { vertical.order(Arel.sql("position ASC NULLS LAST, name ASC")) }
  scope :ordered_horizontal, -> { horizontal.order(:name) }

  def admin?
    vertical? && tenant_owner?
  end

  def full_access?
    permissions_hash["admin"] == true
  end

  def vertical_profile
    associated = super
    return associated if associated.blank? || tenant_id.blank? || associated.tenant_id == tenant_id

    nil
  end

  def manager?
    gerente?
  end

  # Predicados de papel baseados no identificador estável `key` (não no nome).
  # Âncoras podem ser encadeadas (horizontal → horizontal → vertical): a raiz
  # vertical é o nível de hierarquia efetivo de qualquer função operacional.
  def root_vertical_profile
    return self if vertical?

    anchor = vertical_profile
    steps = 0
    while anchor.present? && !anchor.vertical? && steps < 6
      anchor = anchor.vertical_profile
      steps += 1
    end

    anchor&.vertical? ? anchor : nil
  end

  def tenant_owner?   = key == "tenant_owner"
  def administrador?  = tenant_owner?
  def diretor?        = key == "diretor"
  def gerente?        = key == "gerente"
  def administrativo? = key == "administrativo"
  def corretor?       = agent?
  def agent?          = key == "agent"

  def vertical?
    axis == AXES[:vertical]
  end

  def horizontal?
    axis == AXES[:horizontal]
  end

  def self.default_permissions_for(name)
    permissions = PROFILE_PRESETS[name.to_s] || PROFILE_PRESETS["Corretor"]
    permissions.deep_dup
  end

  # Pode fazer `action` sobre `resource`?
  # Ex: profile.can?(:view, :leads) / profile.can?("manage", "imoveis")
  def can?(action, resource)
    return true if admin? || full_access?
    permissions_hash.dig(resource.to_s, action.to_s) == true
  end

  # Retorna o scope configurado pra um recurso:
  #   "own"  — só os próprios registros
  #   "team" — os próprios + a subárvore de gestão (equipe), via AdminUser#team_scope_ids
  #   "all"  — tudo
  # Default "own" quando scopeable e não explicitado.
  def scope_for(resource)
    return "all" if admin?
    return "all" if vertical? && full_access?

    permissions_hash.dig(resource.to_s, "scope") || "own"
  end

  def configured_scope_for(resource)
    permissions_hash.dig(resource.to_s, "scope").presence_in(SCOPE_RANKS.keys)
  end

  def self.restricted_scope(primary_scope, overlay_scope)
    primary = primary_scope.presence_in(SCOPE_RANKS.keys) || "own"
    overlay = overlay_scope.presence_in(SCOPE_RANKS.keys)
    return primary if overlay.blank?

    SCOPE_RANKS.fetch(overlay) < SCOPE_RANKS.fetch(primary) ? overlay : primary
  end

  private

  def assign_default_tenant
    self.tenant ||= Current.tenant
  end

  # Atribui o `key` canônico a partir do nome quando ainda não definido (perfis de
  # sistema criados pela UI/import). Renomear depois não altera o key — comportamento
  # fica preso ao key, nunca ao nome. Não sobrescreve um key existente nem duplica.
  def assign_role_key
    return if key.present?

    normalized = name.to_s.strip
    candidate = ROLE_NAME_KEYS[normalized]
    return unless candidate

    self.key = candidate unless Profile.where(tenant: tenant, key: candidate).where.not(id: id).exists?
  end

  def normalize_axis
    self.axis = AXES[:vertical] if axis.blank?
  end

  def normalize_vertical_position
    if horizontal?
      self.position = nil
    elsif tenant_owner?
      self.position = 0
      self.locked = true
    elsif agent?
      self.position = 10_000
      self.locked = true
    elsif position.blank?
      self.position = next_vertical_position
    end
  end

  def permissions_hash
    (permissions || {}).to_h
  end

  def vertical_profile_rules
    if vertical?
      errors.add(:vertical_profile, "não se aplica a perfil vertical") if vertical_profile_id.present?
      validate_vertical_position_bounds
    elsif horizontal?
      errors.add(:vertical_profile, "é obrigatório para perfil horizontal") if vertical_profile_id.blank?
      assigned_vertical_profile = raw_vertical_profile
      errors.add(:vertical_profile, "deve pertencer ao mesmo Tenant") if assigned_vertical_profile && assigned_vertical_profile.tenant_id != tenant_id
      errors.add(:vertical_profile, "deve ser um perfil vertical") if assigned_vertical_profile && !assigned_vertical_profile.vertical?
    end
  end

  def locked_profile_invariants
    return unless locked?

    unless tenant_owner? || agent?
      errors.add(:locked, "só é permitido para Tenant Owner e Agent")
    end

    if tenant_owner?
      errors.add(:position, "deve manter o topo da hierarquia") unless position.to_i.zero?
      errors.add(:axis, "deve ser vertical") unless vertical?
    elsif agent?
      errors.add(:position, "deve manter o último nível da hierarquia") unless position.to_i == 10_000
      errors.add(:axis, "deve ser vertical") unless vertical?
    end
  end

  def system_vertical_key_uniqueness
    return unless tenant_id.present? && key.in?(ROLE_KEY_NAMES.keys)

    duplicate = Profile.where(tenant_id: tenant_id, key: key).where.not(id: id).exists?
    errors.add(:key, "já existe para este Tenant") if duplicate
  end

  def builtin_profile_axis_invariants
    return if key.blank?

    if key.in?(%w[tenant_owner agent])
      errors.add(:axis, "deve ser vertical para este perfil") unless vertical?
    end
  end

  def vertical_position_uniqueness
    return unless vertical? && tenant_id.present? && position.present?

    duplicate = Profile.where(tenant_id: tenant_id, axis: AXES[:vertical], position: position).where.not(id: id).exists?
    errors.add(:position, "já existe para outro perfil vertical deste Tenant") if duplicate
  end

  def next_vertical_position
    return 100 if tenant.blank?

    max_position = tenant&.profiles&.vertical
      &.where("key IS NULL OR key != ?", "agent")
      &.where("position < ?", 10_000)
      &.maximum(:position)
    [[(max_position || 0) + 100, 100].max, 9_900].min
  end

  def validate_vertical_position_bounds
    return if tenant_owner? || agent?

    if position.blank?
      errors.add(:position, "é obrigatória para perfil vertical customizado")
    elsif position.to_i <= 0 || position.to_i >= 10_000
      errors.add(:position, "deve ficar entre Tenant Owner e Agent")
    end
  end

  def raw_vertical_profile
    Profile.unscoped.find_by(id: vertical_profile_id)
  end
end
