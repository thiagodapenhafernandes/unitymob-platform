class Profile < ApplicationRecord
  has_many :admin_users

  validates :name, presence: true, uniqueness: true
  validates :key, uniqueness: true, allow_nil: true

  # `key` é o identificador ESTÁVEL do papel do sistema, usado pelo código no lugar do
  # nome (que é só rótulo livre e pode ser renomeado sem quebrar comportamento).
  ROLE_KEY_NAMES = {
    "administrador"  => "Administrador",
    "diretor"        => "Diretor",
    "gerente"        => "Gerente",
    "administrativo" => "Administrativo",
    "corretor"       => "Corretor"
  }.freeze

  before_validation :assign_role_key

  # Catálogo de recursos configuráveis via UI em /admin/profiles.
  # Cada entrada define: label humano, ícone, ações disponíveis e se suporta scope own/all.
  RESOURCES = [
    { key: "imoveis",            label: "Imóveis",                icon: "bi-houses",           actions: %w[view manage],       scopeable: true,  description: "Catálogo de imóveis (Habitations)" },
    { key: "leads",              label: "Leads",                  icon: "bi-megaphone",        actions: %w[view manage],       scopeable: true,  description: "Atendimento e gestão de leads" },
    { key: "comercial",          label: "Comercial",              icon: "bi-briefcase",        actions: %w[view manage],       scopeable: true,  description: "Tarefas, agenda e propostas comerciais" },
    { key: "whatsapp_inbox",     label: "Atendimento WhatsApp",   icon: "bi-whatsapp",         actions: %w[view manage],       scopeable: true,  description: "Central de atendimento (inbox) do WhatsApp" },
    { key: "automacoes",         label: "Automação",              icon: "bi-lightning-charge", actions: %w[manage],            scopeable: false, description: "Regras de automação e nutrição de leads" },
    { key: "captacoes",          label: "Captações",              icon: "bi-journal-plus",     actions: %w[view manage review publish], scopeable: true, description: "Intake de imóveis em campo" },
    { key: "captacao_dashboard", label: "Dashboard Captação",     icon: "bi-bullseye",         actions: %w[view],              scopeable: false, description: "Métricas e gauges de captação" },
    { key: "agenda_fotografia",  label: "Agenda de fotografia",   icon: "bi-camera",           actions: %w[view manage],       scopeable: false, description: "Agenda e imóveis pendentes de fotografia" },
    { key: "distribution_rules", label: "Regras de distribuição", icon: "bi-diagram-3",        actions: %w[view manage],       scopeable: false, description: "Distribuição automática de leads" },
    { key: "lojas",              label: "Lojas",                  icon: "bi-shop",             actions: %w[view manage],       scopeable: false, description: "Cadastro de lojas físicas" },
    { key: "field_checkins",     label: "Check-ins em Campo",     icon: "bi-geo-fill",         actions: %w[view manage],       scopeable: false, description: "Monitorar check-ins de corretores em plantão" },
    { key: "field_manual",       label: "Pedidos manuais",        icon: "bi-hand-index-thumb", actions: %w[view manage],       scopeable: false, description: "Aprovar check-ins manuais quando GPS falha" },
    { key: "field_audit",        label: "Auditoria de Campo",     icon: "bi-shield-lock",      actions: %w[view],              scopeable: false, description: "Trilha append-only de eventos de presença" },
    { key: "access_audit",       label: "Auditoria de Acessos",   icon: "bi-person-lock",      actions: %w[view],              scopeable: false, description: "Logins, logouts, IPs, aparelhos e acessos negados" },
    { key: "data_export_audit",  label: "Auditoria de Exportações", icon: "bi-file-earmark-arrow-down", actions: %w[view],     scopeable: false, description: "Exportações CSV, relatórios e impressões de dados" },
    { key: "access_security",    label: "Segurança de Acesso",    icon: "bi-fingerprint",      actions: %w[manage],            scopeable: false, description: "Regras de IP permitido, IP bloqueado e aparelhos confiáveis" },
    { key: "field_settings",     label: "Configurações de Campo", icon: "bi-toggles2",         actions: %w[manage],            scopeable: false, description: "Liga/desliga módulo de presença em campo" },
    { key: "proprietarios",      label: "Proprietários",          icon: "bi-person-vcard",     actions: %w[view manage],       scopeable: false, description: "Cadastro de proprietários" },
    { key: "corretores",         label: "Corretores",             icon: "bi-people",           actions: %w[view manage sync], scopeable: false, description: "Gerenciar AdminUsers" },
    { key: "metas_captacao",     label: "Metas de captação",      icon: "bi-bullseye",         actions: %w[view manage],       scopeable: false, description: "Metas anuais por tipo" },
    { key: "catalogos",          label: "Catálogos dinâmicos",    icon: "bi-tags",             actions: %w[view manage],       scopeable: false, description: "Opções de atributos" },
    { key: "marketing",          label: "Marketing e conteúdo",   icon: "bi-megaphone-fill",   actions: %w[manage],            scopeable: false, description: "Banners, landing, SEO, home, rodapé" },
    { key: "integracoes",        label: "Integrações",            icon: "bi-plug",             actions: %w[manage],            scopeable: false, description: "Meta, DWV, Loft, Portais, Webhooks" },
    { key: "dashboard",          label: "Dashboard principal",    icon: "bi-speedometer2",     actions: %w[view],              scopeable: false, description: "Página inicial do admin" }
  ].freeze

  # Label human-friendly das ações
  ACTION_LABELS = {
    "view"    => "Visualizar",
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
      "imoveis" => { "view" => true, "manage" => false, "scope" => "own" },
      "leads" => { "view" => true, "manage" => true, "scope" => "own" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "own" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" },
      "captacoes" => { "view" => true, "manage" => true, "review" => false, "publish" => true, "scope" => "own" }
    },
    "Administrativo" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "manage" => true, "scope" => "all" },
      "leads" => { "view" => true, "manage" => true, "scope" => "all" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "all" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "all" },
      "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "all" },
      "captacao_dashboard" => { "view" => true },
      "agenda_fotografia" => { "view" => true, "manage" => true },
      "marketing" => { "manage" => true },
      "automacoes" => { "manage" => true }
    },
    "Gerente" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "manage" => true, "scope" => "team" },
      "leads" => { "view" => true, "manage" => true, "scope" => "team" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "team" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "team" },
      "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "team" },
      "captacao_dashboard" => { "view" => true }
    }
  }.freeze

  # Permissão "admin" dá acesso irrestrito a tudo, independente das flags abaixo.
  def admin?
    administrador? || (permissions_hash["admin"] == true)
  end

  def manager?
    gerente?
  end

  # Predicados de papel baseados no identificador estável `key` (não no nome).
  def administrador?  = key == "administrador"
  def diretor?        = key == "diretor"
  def gerente?        = key == "gerente"
  def administrativo? = key == "administrativo"
  def corretor?       = key == "corretor"

  def self.default_permissions_for(name)
    permissions = PROFILE_PRESETS[name.to_s] || PROFILE_PRESETS["Corretor"]
    permissions.deep_dup
  end

  # Pode fazer `action` sobre `resource`?
  # Ex: profile.can?(:view, :leads) / profile.can?("manage", "imoveis")
  def can?(action, resource)
    return true if admin?
    permissions_hash.dig(resource.to_s, action.to_s) == true
  end

  # Retorna o scope configurado pra um recurso:
  #   "own"  — só os próprios registros
  #   "team" — os próprios + a subárvore de gestão (equipe), via AdminUser#team_scope_ids
  #   "all"  — tudo
  # Default "own" quando scopeable e não explicitado.
  def scope_for(resource)
    return "all" if admin?
    permissions_hash.dig(resource.to_s, "scope") || "own"
  end

  private

  # Atribui o `key` canônico a partir do nome quando ainda não definido (perfis de
  # sistema criados pela UI/import). Renomear depois não altera o key — comportamento
  # fica preso ao key, nunca ao nome. Não sobrescreve um key existente nem duplica.
  def assign_role_key
    return if key.present?

    normalized = name.to_s.strip
    match = ROLE_KEY_NAMES.find { |_k, canonical| canonical.casecmp?(normalized) }
    return unless match

    candidate = match.first
    self.key = candidate unless Profile.where(key: candidate).where.not(id: id).exists?
  end

  def permissions_hash
    (permissions || {}).to_h
  end
end
