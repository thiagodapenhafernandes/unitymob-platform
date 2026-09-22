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
  HABITATION_SEARCH_STATUSES_PERMISSION_KEY = "search_statuses".freeze
  MENU_ORDER_PERMISSION_KEY = "_menu_order".freeze
  SIDEBAR_SECTION_DEFINITIONS = [
    { key: :product, label: "Produto", icon: "bi-grid-1x2" },
    { key: :operation, label: "Operação", icon: "bi-briefcase" },
    { key: :management, label: "Gestão", icon: "bi-people" },
    { key: :growth, label: "Crescimento", icon: "bi-graph-up-arrow" },
    { key: :public_site, label: "Site público", icon: "bi-globe2" },
    { key: :integrations, label: "Integrações", icon: "bi-plug" },
    { key: :settings, label: "Configurações", icon: "bi-sliders" },
    { key: :account, label: "Conta", icon: "bi-building-gear" }
  ].freeze
  INTERNAL_PERMISSION_SECTION = { key: :internal, label: "Permissões internas", icon: "bi-shield-check" }.freeze
  INTERNAL_PERMISSION_SECTION_BY_RESOURCE = {
    "lead_reports" => :product,
    "dashboard_broker_performance" => :product,
    "dashboard_campaign_performance" => :product
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
  before_validation :normalize_habitation_field_locks

  # Catálogo único do módulo Perfil/Permissão.
  #
  # Como incluir um novo módulo:
  # 1. Cadastre o recurso aqui com `key`, `actions`, `scopeable`, `label` e `description`.
  # 2. Se ele abre uma seção inteira do menu, marque `section: true`.
  # 3. Se ele pertence a uma seção/tela pai, use `parent_section`.
  #    Ex.: `dashboard_broker_performance` fica dentro de `dashboard_leads`;
  #    `access_security` fica dentro de `conta`. Se o pai for negado, os filhos
  #    também são negados no backend.
  # 4. Se deve aparecer no menu lateral, informe `sidebar_section`,
  #    `sidebar_actions` e `sidebar_items`; o helper monta/oculta o menu daqui.
  #    A tela de Perfil/Permissão usa essa mesma ordem do sidebar.
  # 5. Se a tela tem abas/blocos internos, prefira recurso real + `parent_section`
  #    quando houver trava funcional. Use `permission_items` só para listar blocos
  #    herdados/informativos, sem permissão própria ainda.
  # 6. No controller, declare `requires_permission :acao, :recurso`.
  #
  # A intenção é evitar regras por nome de perfil. Perfis verticais/horizontais
  # podem variar por conta; o sistema deve olhar para permissões configuradas.
  RESOURCES = [
    # Imóveis e Leads: `manage` desmembrado em create/edit/delete (Fase 2).
    { key: "imoveis",            label: "Imóveis",                icon: "bi-houses",           actions: %w[view media create edit delete], scopeable: true, sidebar_section: "product", sidebar_actions: %w[view], sidebar_items: [
      { label: "Imóveis", icon: "bi-houses", path: "admin_habitations_path", path_params: { ownership: "all" }, controllers: %w[habitations] }
    ], description: "Catálogo de imóveis, mídia e uploads" },
    { key: "leads",              label: "Leads",                  icon: "bi-megaphone",        actions: %w[view create edit delete], scopeable: true,  sidebar_section: "product", sidebar_actions: %w[view], sidebar_items: [
      { label: "Leads", icon: "bi-person-badge", path: "admin_leads_path", path_params: { view: "list" }, controllers: %w[leads], inactive_actions: %w[lead_pool], inactive_params: [:lead_pipeline_id] }
    ], description: "Atendimento e gestão de leads" },
    { key: "lead_pool",          label: "Bolsão",                 icon: "bi-people",           actions: %w[view],              scopeable: true,  sidebar_section: "product", sidebar_actions: %w[view], sidebar_items: [
      { label: "Bolsão", icon: "bi-people", path: "lead_pool_admin_leads_path", controllers: %w[leads], active_actions: %w[lead_pool] }
    ], description: "Leads disponíveis para a equipe assumir" },
    { key: "lead_funnels",       label: "Funil",                  icon: "bi-diagram-3",        actions: %w[view],              scopeable: false, sidebar_section: "product", sidebar_actions: %w[view], sidebar_items: [
      { group: "Funil", icon: "bi-diagram-3", dynamic: "lead_pipelines" }
    ], description: "Menus de funis comerciais por tipo de operação" },
    { key: "lead_funnel_rental", label: "Locação",                icon: "bi-kanban",           actions: %w[view],              scopeable: false, parent_section: "lead_funnels", description: "Funil de leads de locação" },
    { key: "lead_funnel_sale",   label: "Vendas",                 icon: "bi-kanban",           actions: %w[view],              scopeable: false, parent_section: "lead_funnels", description: "Funil de leads de venda" },
    { key: "lead_reports",       label: "Relatórios de leads",    icon: "bi-filetype-xlsx",    actions: %w[view],              scopeable: false, parent_section: "leads", description: "Gerar relatórios e exportações da carteira de leads" },
    { key: "dashboard_broker_performance", label: "Performance dos Corretores", icon: "bi-person-lines-fill", actions: %w[view], scopeable: true, parent_section: "dashboard_leads", description: "Bloco e relatório de ciclo dos leads por corretor no dashboard" },
    { key: "dashboard_campaign_performance", label: "Performance de Campanhas", icon: "bi-signpost-split", actions: %w[view], scopeable: true, parent_section: "dashboard_leads", description: "Bloco e relatório de campanhas, canais e avanço comercial no dashboard" },
    { key: "comercial",          label: "Comercial",              icon: "bi-briefcase",        actions: %w[view manage],       scopeable: true,  sidebar_section: "operation", sidebar_actions: %w[view], sidebar_items: [
      { group: "Comercial", icon: "bi-briefcase", controllers: %w[tasks appointments proposals commercial_contract_proposals], children: [
        { label: "Minhas Tarefas", icon: "bi-check2-square", path: "admin_tasks_path", controllers: %w[tasks] },
        { label: "Agenda", icon: "bi-calendar-event", path: "admin_appointments_path", controllers: %w[appointments] },
        { label: "Contratos B2B", icon: "bi-file-earmark-check", path: "admin_commercial_contract_proposals_path", controllers: %w[commercial_contract_proposals], permission: [:manage, :commercial_contracts] }
      ] }
    ], description: "Tarefas, agenda e propostas comerciais" },
    { key: "commercial_contracts", label: "Contratos B2B", icon: "bi-file-earmark-check", actions: %w[manage], scopeable: false, parent_section: "comercial", description: "Propostas comerciais B2B, termos e PDFs de contratação" },
    { key: "whatsapp_inbox",     label: "Atendimento WhatsApp",   icon: "bi-whatsapp",         actions: %w[view manage],       scopeable: true,  sidebar_section: "operation", sidebar_actions: %w[view], sidebar_items: [
      { group: "WhatsApp", icon: "bi-whatsapp", controllers: %w[whatsapp_inbox whatsapp_attendances whatsapp_campaigns whatsapp_templates whatsapp_response_flows], permission_any: [[:view, :whatsapp_inbox], [:view, :whatsapp_campaigns], [:view, :whatsapp_response_flows]], children: [
        { label: "Atendimento", icon: "bi-chat-dots", path: "admin_whatsapp_conversations_path", controllers: %w[whatsapp_inbox], permission: [:view, :whatsapp_inbox] },
        { label: "Gestão de atendimentos", icon: "bi-headset", path: "admin_whatsapp_attendances_path", controllers: %w[whatsapp_attendances], permission: [:view, :whatsapp_inbox] },
        { label: "Templates", icon: "bi-grid-3x2-gap", path: "admin_whatsapp_templates_path", controllers: %w[whatsapp_templates], permission: [:view, :whatsapp_campaigns] },
        { label: "Fluxos de Resposta", icon: "bi-diagram-3", path: "admin_whatsapp_response_flows_path", controllers: %w[whatsapp_response_flows], permission: [:view, :whatsapp_response_flows] },
        { label: "Disparos", icon: "bi-broadcast", path: "admin_whatsapp_campaigns_path", controllers: %w[whatsapp_campaigns], permission: [:view, :whatsapp_campaigns] }
      ] }
    ], description: "Central de atendimento (inbox) do WhatsApp" },
    { key: "whatsapp_response_flows", label: "Fluxos de Resposta WhatsApp", icon: "bi-diagram-3", actions: %w[view manage], scopeable: true, sidebar_section: "operation", sidebar_actions: %w[view], description: "Mapeamento de botões aprovados para mensagens, links, tarefas e filas de atendimento" },
    { key: "whatsapp_campaigns", label: "Disparos WhatsApp",      icon: "bi-send",             actions: %w[view manage],       scopeable: true,  sidebar_section: "operation", sidebar_actions: %w[view], description: "Campanhas e disparos em massa pelo WhatsApp" },
    { key: "automacoes",         label: "Automação",              icon: "bi-lightning-charge", actions: %w[manage],            scopeable: false, sidebar_section: "operation", sidebar_actions: %w[manage], sidebar_items: [
      { label: "Automação", icon: "bi-lightning-charge", path: "admin_automation_rules_path", controllers: %w[automation_rules automation_workflows automation_events] }
    ], description: "Regras de automação e nutrição de leads" },
    { key: "captacoes",          label: "Captações",              icon: "bi-journal-plus",     actions: %w[view manage review publish], scopeable: true, sidebar_section: "operation", sidebar_actions: %w[view], sidebar_items: [
      { label: "Captações", icon: "bi-journal-plus", path: "admin_captacoes_path", controllers: %w[habitation_intakes] }
    ], description: "Intake de imóveis em campo" },
    { key: "captacao_dashboard", label: "Dashboard Captação",     icon: "bi-bullseye",         actions: %w[view manage],       scopeable: false, sidebar_section: "operation", sidebar_actions: %w[view], sidebar_items: [
      { label: "Dashboard Captação", icon: "bi-bullseye", path: "dashboard_admin_captacoes_path", controllers: %w[captacoes], active_actions: %w[dashboard] }
    ], description: "Métricas e gauges de captação" },
    { key: "agenda_fotografia",  label: "Agenda de fotografia",   icon: "bi-camera",           actions: %w[view manage],       scopeable: false, parent_section: "integracoes", description: "Agenda e imóveis pendentes de fotografia" },
    { key: "distribution_rules", label: "Regras de distribuição", icon: "bi-diagram-3",        actions: %w[view manage],       scopeable: false, sidebar_section: "operation", sidebar_actions: %w[manage], sidebar_items: [
      { label: "Distribuição de Leads", icon: "bi-diagram-3", path: "admin_distribution_rules_path", controllers: %w[distribution_rules] }
    ], description: "Distribuição automática de leads" },
    { key: "lojas",              label: "Lojas",                  icon: "bi-shop",             actions: %w[view manage],       scopeable: false, sidebar_section: "management", sidebar_actions: %w[view manage], sidebar_items: [
      { label: "Lojas", icon: "bi-shop", path: "admin_stores_path", controllers: %w[stores] }
    ], description: "Cadastro de lojas físicas" },
    { key: "field_checkins",     label: "Check-ins em Campo",     icon: "bi-geo-fill",         actions: %w[view manage],       scopeable: false, sidebar_section: "operation", sidebar_actions: %w[view], sidebar_items: [
      { label: "Check-ins em Campo", icon: "bi-geo-fill", path: "admin_field_check_ins_path", controller_paths: %w[admin/field/check_ins] }
    ], description: "Monitorar check-ins de corretores em plantão" },
    { key: "field_manual",       label: "Pedidos manuais",        icon: "bi-hand-index-thumb", actions: %w[view manage],       scopeable: false, sidebar_section: "operation", sidebar_actions: %w[view], sidebar_items: [
      { label: "Pedidos manuais", icon: "bi-hand-index-thumb-fill", path: "admin_field_manual_checkin_requests_path", controller_paths: %w[admin/field/manual_checkin_requests] }
    ], description: "Aprovar check-ins manuais quando GPS falha" },
    { key: "field_audit",        label: "Auditoria de Campo",     icon: "bi-shield-lock",      actions: %w[view],              scopeable: true,  parent_section: "conta", description: "Trilha append-only de eventos de presença" },
    { key: "access_audit",       label: "Auditoria de Acessos",   icon: "bi-person-lock",      actions: %w[view],              scopeable: true,  parent_section: "conta", description: "Logins, logouts, IPs, aparelhos e acessos negados" },
    { key: "data_export_audit",  label: "Auditoria de Exportações", icon: "bi-file-earmark-arrow-down", actions: %w[view],     scopeable: true,  parent_section: "conta", description: "Exportações CSV, relatórios e impressões de dados" },
    { key: "access_security",    label: "Segurança de Acesso",    icon: "bi-fingerprint",      actions: %w[manage],            scopeable: true,  parent_section: "conta", description: "Regras de IP permitido, IP bloqueado e aparelhos confiáveis" },
    { key: "field_settings",     label: "Configurações de Campo", icon: "bi-toggles2",         actions: %w[manage],            scopeable: false, parent_section: "configuracoes", description: "Liga/desliga módulo de presença em campo" },
    { key: "proprietarios",      label: "Proprietários",          icon: "bi-person-vcard",     actions: %w[view manage],       scopeable: false, sidebar_section: "management", sidebar_actions: %w[view], sidebar_items: [
      { label: "Proprietários", icon: "bi-person-vcard", path: "admin_proprietors_path", controllers: %w[proprietors] }
    ], description: "Cadastro de proprietários" },
    { key: "corretores",         label: "Corretores",             icon: "bi-people",           actions: %w[view manage sync], scopeable: false, sidebar_section: "management", sidebar_actions: %w[manage], sidebar_items: [
      { label: "Usuários", icon: "bi-people", path: "admin_admin_users_path", controllers: %w[admin_users] }
    ], description: "Gerenciar AdminUsers" },
    { key: "metas_captacao",     label: "Metas de captação",      icon: "bi-bullseye",         actions: %w[view manage],       scopeable: false, sidebar_section: "management", sidebar_actions: %w[view], sidebar_items: [
      { label: "Metas de Captação", icon: "bi-bullseye", path: "admin_captacao_goals_path", controllers: %w[captacao_goals] }
    ], description: "Metas anuais por tipo" },
    { key: "catalogos",          label: "Catálogos dinâmicos",    icon: "bi-tags",             actions: %w[view manage],       scopeable: false, parent_section: "configuracoes", description: "Opções de atributos" },
    { key: "marketing",          label: "Marketing e conteúdo",   icon: "bi-megaphone-fill",   actions: %w[manage],            scopeable: false, section: true, sidebar_section: "growth", sidebar_actions: %w[manage], included_items: ["Oportunidades", "Campanhas", "UTM Builder", "Imóveis com Potencial", "Alertas"], sidebar_items: [
      { label: "Oportunidades", icon: "bi-lightbulb", path: "admin_marketing_opportunities_path", controllers: %w[marketing_opportunities] },
      { label: "Campanhas", icon: "bi-bullseye", path: "admin_marketing_campaigns_path", controllers: %w[marketing_campaigns] },
      { label: "UTM Builder", icon: "bi-link-45deg", path: "admin_marketing_tools_path", controllers: %w[marketing_tools] },
      { label: "Imóveis com Potencial", icon: "bi-house-heart", path: "admin_marketing_properties_path", controllers: %w[marketing_properties] },
      { label: "Alertas", icon: "bi-exclamation-triangle", path: "admin_marketing_alerts_path", controllers: %w[marketing_alerts] }
    ], description: "Banners, landing, SEO, home, rodapé" },
    { key: "site_publico",       label: "Site público",           icon: "bi-globe2",           actions: %w[manage],            scopeable: false, section: true, sidebar_section: "public_site", sidebar_actions: %w[manage], included_items: ["Dashboard SEO", "Páginas SEO", "Redirecionamentos SEO", "Formulários", "Blog", "Landing Pages", "Banners", "Seções da Home", "Identidade", "Topo e menu", "Home", "Contato", "Rodapé", "Perfil público"], sidebar_items: [
      { caption: "SEO" },
      { label: "Dashboard SEO", icon: "bi-graph-up-arrow", path: "admin_seo_dashboard_path", controllers: %w[seo_dashboard] },
      { label: "Páginas SEO", icon: "bi-search", path: "admin_seo_settings_path", controllers: %w[seo_settings] },
      { label: "Redirecionamentos SEO", icon: "bi-signpost-split", path: "admin_seo_redirects_path", controllers: %w[seo_redirects] },
      { caption: "Conteúdo" },
      { label: "Formulários", icon: "bi-ui-checks-grid", path: "admin_public_forms_path", controllers: %w[public_forms] },
      { label: "Blog", icon: "bi-journal-richtext", path: "admin_blog_articles_path", controllers: %w[blog_articles] },
      { label: "Landing Pages", icon: "bi-file-earmark-post", path: "admin_landing_pages_path", controllers: %w[landing_pages] },
      { label: "Banners", icon: "bi-image", path: "admin_banners_path", controllers: %w[banners] },
      { label: "Seções da Home", icon: "bi-layout-text-sidebar", path: "admin_home_sections_path", controllers: %w[home_sections] },
      { caption: "Estrutura" },
      { label: "Identidade", icon: "bi-stars", path: "edit_admin_public_identity_path", controllers: %w[public_identities] },
      { label: "Topo e menu", icon: "bi-layout-text-window", path: "edit_admin_public_header_path", controllers: %w[public_headers] },
      { label: "Home", icon: "bi-house-door", path: "edit_admin_home_setting_path", controllers: %w[home_settings] },
      { label: "Contato", icon: "bi-telephone", path: "edit_admin_contact_setting_path", controllers: %w[contact_settings] },
      { label: "Rodapé", icon: "bi-layout-sidebar", path: "edit_admin_footer_setting_path", controllers: %w[footer_settings] },
      { label: "Perfil público", icon: "bi-building-gear", path: "edit_admin_public_site_profile_path", controllers: %w[public_site_profiles] }
    ], description: "SEO, páginas, blog e estrutura do site público" },
    { key: "integracoes",        label: "Integrações",            icon: "bi-plug",             actions: %w[manage],            scopeable: false, section: true, sidebar_section: "integrations", sidebar_actions: %w[manage], included_items: ["Portais", "Loft Soft", "DWV", "WhatsApp", "Meta Leads", "RD Station", "Lovers", "Google", "Rastreamento", "Migração de Leads", "Armazenamento", "Agendamento", "Webhooks", "IA", "Imóveis sincronizados", "Migração de Imagens"], sidebar_items: [
      { label: "Portais", icon: "bi-building", path: "admin_portal_integrations_path", controllers: %w[portal_integrations] },
      { label: "Loft Soft", icon: "bi-hdd-rack", path: "admin_loft_integrations_path", controllers: %w[loft_integrations] },
      { label: "DWV", icon: "bi-hdd-network", path: "admin_dwv_integrations_path", controllers: %w[dwv_integrations] },
      { label: "WhatsApp", icon: "bi-whatsapp", path: "admin_whatsapp_integration_path", controllers: %w[whatsapp_integrations] },
      { label: "Meta Leads", icon: "bi-meta", path: "admin_meta_integrations_path", controllers: %w[meta_integrations] },
      { label: "RD Station", icon: "bi-envelope-paper", path: "admin_rd_station_integration_path", controllers: %w[rd_station_integrations] },
      { label: "Lovers", icon: "bi-heart", path: "admin_lovers_integration_path", controllers: %w[lovers_integrations] },
      { label: "Google", icon: "bi-google", path: "admin_google_integration_path", controllers: %w[google_integrations] },
      { label: "Rastreamento", icon: "bi-bullseye", path: "admin_tracking_integration_path", controllers: %w[tracking_integrations] },
      { label: "Migração de Leads", icon: "bi-arrow-left-right", path: "admin_external_lead_integration_path", controllers: %w[external_lead_integrations] },
      { label: "Armazenamento", icon: "bi-cloud-arrow-up", path: "admin_storage_integration_path", controllers: %w[storage_integrations] },
      { label: "Agendamento", icon: "bi-calendar2-check", path: "admin_scheduling_integration_path", controllers: %w[scheduling_integrations], permission: [:view, :agenda_fotografia] },
      { label: "Webhooks", icon: "bi-broadcast", path: "admin_webhook_settings_path", controllers: %w[webhook_settings] },
      { label: "IA", icon: "bi-stars", path: "admin_ai_integration_path", controllers: %w[ai_integrations] },
      { label: "Imóveis sincronizados", icon: "bi-arrow-repeat", path: "admin_habitations_path", path_params: { sort: "last_sync_at", direction: "desc" }, controllers: %w[habitations], active_params: { sort: "last_sync_at" }, permission_all: [[:manage, :integracoes], [:view, :imoveis]] },
      { label: "Migração de Imagens", icon: "bi-images", path: "admin_image_migration_status_path", controllers: %w[image_migration_status] }
    ], description: "Meta, DWV, Loft, Portais, Webhooks" },
    { key: "configuracoes",      label: "Configurações",          icon: "bi-sliders",          actions: %w[manage],            scopeable: false, section: true, sidebar_section: "settings", sidebar_actions: %w[manage], included_items: ["Configurações de Leads", "Atendimento WhatsApp", "Catálogos Dinâmicos", "Configuração de Imóveis", "Fluxo de revisão", "Configurações de Campo"], sidebar_items: [
      { label: "Configurações de Leads", icon: "bi-person-check", path: "edit_admin_lead_setting_path", controllers: %w[lead_settings] },
      { label: "Atendimento WhatsApp", icon: "bi-whatsapp", path: "edit_admin_whatsapp_service_setting_path", controllers: %w[whatsapp_service_settings], condition: "whatsapp_service_ready" },
      { label: "Catálogos Dinâmicos", icon: "bi-tags", path: "admin_attribute_options_path", controllers: %w[attribute_options] },
      { label: "Configuração de Imóveis", icon: "bi-house-gear", path: "edit_admin_property_setting_path", controllers: %w[property_settings], active_actions: %w[edit update] },
      { label: "Fluxo de revisão", icon: "bi-diagram-3", path: "review_workflow_admin_property_setting_path", controllers: %w[property_settings], active_actions: %w[review_workflow update_review_workflow] },
      { caption: "Campo" },
      { label: "Configurações de Campo", icon: "bi-toggles2", path: "edit_admin_field_settings_path", controllers: %w[field_settings] }
    ], description: "Configurações gerais da conta operacional" },
    { key: "conta",              label: "Conta",                  icon: "bi-building-gear",    actions: %w[manage],            scopeable: false, section: true, sidebar_section: "account", sidebar_actions: %w[manage], included_items: ["Visão geral", "Aparência da plataforma", "Perfis", "Meu SMTP", "Importados CSV", "Descadastros WhatsApp", "Segurança de Acesso", "Auditoria Operacional", "Auditoria de Campo", "Auditoria de Acessos", "Auditoria de Exportações", "Apresentações WhatsApp"], sidebar_items: [
      { label: "Visão geral", icon: "bi-grid-1x2", path: "admin_account_settings_path", controllers: %w[account_settings] },
      { label: "Aparência da plataforma", icon: "bi-palette", path: "edit_admin_layout_setting_path", controllers: %w[layout_settings] },
      { label: "Perfis", icon: "bi-shield-lock", path: "admin_profiles_path", controllers: %w[profiles] },
      { caption: "Notificações" },
      { label: "Meu SMTP", icon: "bi-envelope-at", path: "edit_admin_email_setting_path", controllers: %w[email_settings] },
      { caption: "WhatsApp" },
      { label: "Importados CSV", icon: "bi-table", path: "admin_whatsapp_campaign_recipients_path", controllers: %w[whatsapp_campaign_recipients] },
      { label: "Descadastros WhatsApp", icon: "bi-person-dash", path: "admin_whatsapp_campaign_unsubscribes_path", controllers: %w[whatsapp_campaign_unsubscribes] },
      { caption: "Segurança" },
      { label: "Segurança de Acesso", icon: "bi-fingerprint", path: "admin_access_security_path", controllers: %w[access_security], permission: [:manage, :access_security] },
      { caption: "Auditorias" },
      { label: "Auditoria Operacional", icon: "bi-activity", path: "admin_user_activity_sessions_path", controllers: %w[user_activity_sessions] },
      { label: "Auditoria de Campo", icon: "bi-shield-lock-fill", path: "admin_field_audit_logs_path", controller_paths: %w[admin/field/audit_logs], permission: [:view, :field_audit] },
      { label: "Auditoria de Acessos", icon: "bi-person-lock", path: "admin_access_audit_logs_path", controllers: %w[access_audit_logs], permission: [:view, :access_audit] },
      { label: "Auditoria de Exportações", icon: "bi-file-earmark-arrow-down", path: "admin_data_export_audit_logs_path", controllers: %w[data_export_audit_logs], permission: [:view, :data_export_audit] },
      { label: "Apresentações WhatsApp", icon: "bi-person-badge", path: "admin_presentation_audit_logs_path", controllers: %w[presentation_audit_logs], permission: [:view, :access_audit] }
    ], description: "Dados, marca, perfis, segurança e auditorias da conta" },
    { key: "inbound_webhooks",   label: "Webhook de entrada",     icon: "bi-box-arrow-in-down", actions: %w[manage],           scopeable: false, parent_section: "integracoes", description: "Token pessoal para receber leads por webhook dentro da seção Integrações" },
    { key: "dashboard",          label: "Dashboard principal",    icon: "bi-speedometer2",     actions: %w[view],              scopeable: false, sidebar_section: "product", sidebar_actions: %w[view], sidebar_items: [
      { dynamic: "dashboard_home", icon: "bi-speedometer2", controllers: %w[dashboard] }
    ], description: "Página inicial do admin" },
    { key: "dashboard_leads",    label: "Aba Leads",             icon: "bi-megaphone",        actions: %w[view],              scopeable: false, parent_section: "dashboard", permission_items: [
      { label: "Aba Leads", description: "Performance, aquisição, gráficos, status e funil", items: [
        { label: "Performance dos Corretores", resource: "dashboard_broker_performance" },
        { label: "Performance de Campanhas", resource: "dashboard_campaign_performance" },
        { label: "Aquisição, gráficos, status e funil", inherits: "dashboard_leads" }
      ] }
    ], description: "Performance, aquisição, gráficos, status e funil do dashboard" },
    { key: "dashboard_properties", label: "Aba Imóveis",          icon: "bi-buildings",        actions: %w[view],              scopeable: false, parent_section: "dashboard", permission_items: [
      { label: "Aba Imóveis", description: "Operação, rankings e suporte do catálogo", items: [
        { label: "Operação e rankings de imóveis", inherits: "dashboard_properties" },
        { label: "Suporte, oferta e demanda", inherits: "dashboard_properties" }
      ] }
    ], description: "Operação, rankings e suporte do catálogo no dashboard" },
    { key: "dashboard_site",     label: "Aba Site público",       icon: "bi-globe2",           actions: %w[view],              scopeable: false, parent_section: "dashboard", permission_items: [
      { label: "Aba Site público", description: "Navegação, conversões e intenção no site", items: [
        { label: "Navegação e conversões", inherits: "dashboard_site" },
        { label: "Imóveis e buscas com atenção", inherits: "dashboard_site" }
      ] }
    ], description: "Navegação, conversões e intenção no site público" },
    { key: "dashboard_overview", label: "Aba Visão geral",        icon: "bi-grid-1x2",         actions: %w[view],              scopeable: false, parent_section: "dashboard", permission_items: [
      { label: "Aba Visão geral", description: "Resumo executivo e ações recomendadas", items: [
        { label: "Ações recomendadas", inherits: "dashboard_overview" },
        { label: "Mapa de investigação operacional", inherits: "dashboard_overview" }
      ] }
    ], description: "Resumo executivo e ações recomendadas do dashboard" },
    { key: "dashboard_field",    label: "Aba Campo",              icon: "bi-geo-alt",          actions: %w[view],              scopeable: false, parent_section: "dashboard", permission_items: [
      { label: "Aba Campo", description: "Aparece quando o módulo Campo está ativo", items: [
        { label: "Top lojas por check-ins", inherits: "dashboard_field" },
        { label: "Operação de campo", inherits: "dashboard_field" }
      ] }
    ], description: "Blocos de campo e check-ins no dashboard" }
  ].freeze
  RESOURCE_INDEX = RESOURCES.index_by { |resource| resource.fetch(:key) }.freeze
  SECTION_RESOURCE_KEYS = RESOURCES.select { |resource| resource[:section] }.map { |resource| resource.fetch(:key) }.freeze

  # Label human-friendly das ações
  # Nenhuma ação implica outra: can? é lookup plano, então cada switch é uma
  # decisão explícita ("gerencia mas não exclui" só existe por isso).
  #
  # `manage` é o balde legado (criar + editar juntos) e segue valendo nos recursos
  # ainda não desmembrados. Imóveis e Leads já usam create/edit/delete separados —
  # neles `manage` não é mais lido por ninguém.
  #
  # A ordem deste hash é a ordem das colunas da matriz em /admin/profiles.
  ACTION_LABELS = {
    "view"    => "Visualizar",
    "media"   => "Mídia",
    "create"  => "Criar",
    "edit"    => "Editar",
    "manage"  => "Gerenciar",
    "delete"  => "Excluir",
    "review"  => "Aprovar",
    "publish" => "Publicar",
    "sync"    => "Sincronizar"
  }.freeze

  # Presets = ponto de partida de perfil NOVO (find_or_create_by! só roda o bloco
  # na criação; perfis existentes não são tocados). Exclusão nasce desligada em
  # todos: só o Administrador (admin => true) exclui por padrão. Quem precisar
  # liga o switch — excluir é opt-in consciente, não herança de "gerenciar".
  PROFILE_PRESETS = {
    "Administrador" => {
      "admin" => true
    },
    "Corretor" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "dashboard_leads" => { "view" => true },
      "dashboard_properties" => { "view" => true },
      "dashboard_site" => { "view" => true },
      "dashboard_overview" => { "view" => true },
      "dashboard_field" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => false, "edit" => false, "delete" => false, "scope" => "own" },
      "leads" => { "view" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "own" },
      "lead_pool" => { "view" => true, "scope" => "own" },
      "lead_funnels" => { "view" => true },
      "lead_funnel_rental" => { "view" => true },
      "lead_funnel_sale" => { "view" => true },
      "comercial" => { "view" => true, "manage" => true, "scope" => "own" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" },
      "captacoes" => { "view" => true, "manage" => true, "review" => false, "publish" => true, "scope" => "own" }
    },
    "Administrativo" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "dashboard_leads" => { "view" => true },
      "dashboard_properties" => { "view" => true },
      "dashboard_site" => { "view" => true },
      "dashboard_overview" => { "view" => true },
      "dashboard_field" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "all" },
      "leads" => { "view" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "all" },
      "lead_pool" => { "view" => true, "scope" => "all" },
      "lead_funnels" => { "view" => true },
      "lead_funnel_rental" => { "view" => true },
      "lead_funnel_sale" => { "view" => true },
      "lead_reports" => { "view" => true },
      "dashboard_broker_performance" => { "view" => true, "scope" => "all" },
      "dashboard_campaign_performance" => { "view" => true, "scope" => "all" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "all" },
      "commercial_contracts" => { "manage" => true },
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
      "dashboard_leads" => { "view" => true },
      "dashboard_properties" => { "view" => true },
      "dashboard_site" => { "view" => true },
      "dashboard_overview" => { "view" => true },
      "dashboard_field" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "team" },
      "leads" => { "view" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "team" },
      "lead_pool" => { "view" => true, "scope" => "team" },
      "lead_funnels" => { "view" => true },
      "lead_funnel_rental" => { "view" => true },
      "lead_funnel_sale" => { "view" => true },
      "lead_reports" => { "view" => true },
      "dashboard_broker_performance" => { "view" => true, "scope" => "team" },
      "dashboard_campaign_performance" => { "view" => true, "scope" => "team" },
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

  def self.section_resource?(resource)
    SECTION_RESOURCE_KEYS.include?(resource.to_s)
  end

  def self.resource_for(resource)
    RESOURCE_INDEX[resource.to_s]
  end

  def self.parent_section_for(resource)
    RESOURCE_INDEX.dig(resource.to_s, :parent_section)
  end

  def self.parent_section_action_for(resource)
    parent = resource_for(parent_section_for(resource))
    return nil if parent.blank?

    # Seção macro administrativa costuma usar `manage` (Conta, Integrações,
    # Configurações). Telas de leitura, como Dashboard, usam `view`; por isso o
    # filho deve exigir a ação primária real do pai, e não `manage` fixo.
    Array(parent[:actions]).include?("manage") ? :manage : :view
  end

  def self.permission_children_for(resource)
    RESOURCES.select { |child| child[:parent_section].to_s == resource.to_s }
  end

  # A árvore de Perfil/Permissão deve seguir a ordem do menu lateral. Recursos
  # internos sem item próprio no sidebar entram depois, preservando o diagnóstico
  # do que existe no backend mas ainda não aparece como menu direto.
  def self.sidebar_resource_order_for(section, profile: nil)
    keys = sidebar_items_for(section, profile: profile).flat_map { |item| sidebar_item_resource_keys(item) }
    keys.uniq
  end

  def self.sidebar_menu_count_for(section)
    sidebar_items_for(section).sum { |item| sidebar_item_menu_count(item) }
  end

  # Extrai recursivamente quais recursos um item do sidebar controla. Grupos e
  # itens dinâmicos entram pela `permission`/`permission_any` já normalizada em
  # `sidebar_items_for`, mantendo sidebar e matriz de permissões no mesmo contrato.
  def self.sidebar_item_resource_keys(item)
    explicit_permissions = Array(item[:permission_all])
    explicit_permissions += Array(item[:permission_any]).presence || [item[:permission]].compact
    keys = explicit_permissions.filter_map { |_action, resource| resource&.to_s }
    keys += Array(item[:children]).flat_map { |child| sidebar_item_resource_keys(child) }
    keys
  end

  def self.sidebar_item_menu_count(item)
    return 0 if item[:caption].present?

    children = Array(item[:children])
    return children.sum { |child| sidebar_item_menu_count(child) } if children.any?

    if item[:dynamic].to_s == "lead_pipelines"
      # O sidebar gera Locação/Vendas a partir dos funis ativos. Na matriz de
      # permissões estes submenus são os filhos estáveis de `lead_funnels`.
      return permission_children_for(:lead_funnels).size
    end

    1
  end

  def self.sidebar_permissions_for(section)
    RESOURCES.flat_map do |resource|
      next [] unless resource[:sidebar_section].to_s == section.to_s

      Array(resource[:sidebar_actions]).map { |action| [action.to_sym, resource.fetch(:key).to_sym] }
    end
  end

  def self.sidebar_items_for(section, profile: nil)
    # Itens sem `permission` explícita herdam as permissões declaradas em
    # `sidebar_actions`. Assim, menu e backend continuam apontando para o
    # mesmo recurso do catálogo, sem duplicar a regra na partial do sidebar.
    sidebar_resources_for(section, profile: profile).flat_map do |resource|
      default_permissions = Array(resource[:sidebar_actions]).map { |action| [action.to_sym, resource.fetch(:key).to_sym] }
      Array(resource[:sidebar_items]).map do |item|
        next item if item[:caption].present? || item[:permission].present? || item[:permission_any].present? || item[:permission_all].present?

        item.merge(permission_any: default_permissions)
      end
    end
  end

  def self.sidebar_resources_for(section, profile: nil)
    resources = default_sidebar_resources_for(section)
    order = menu_order_for(profile, section)
    return resources if order.blank?

    positions = order.each_with_index.to_h
    resources.sort_by.with_index { |resource, index| [positions.fetch(resource.fetch(:key).to_s, positions.size + index), index] }
  end

  def self.default_sidebar_resources_for(section)
    resources = RESOURCES.select { |resource| resource[:sidebar_section].to_s == section.to_s }
    return resources unless section.to_s == "product"

    resources.sort_by { |resource| resource.fetch(:key) == "dashboard" ? -1 : 0 }
  end

  # Ordem customizada do menu fica no próprio JSON de permissões do perfil.
  # Ao adicionar novos menus no catálogo, não crie migração nem regra avulsa:
  # o normalizador abaixo aceita apenas chaves válidas da seção e deixa qualquer
  # recurso novo aparecer no fim até alguém reordenar pelo Perfil/Permissão.
  def self.normalize_menu_order(raw)
    raw_hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    raw_hash.each_with_object({}) do |(section, values), normalized|
      allowed = default_sidebar_resources_for(section).map { |resource| resource.fetch(:key).to_s }
      ordered = Array(values).map(&:to_s).select { |key| allowed.include?(key) }.uniq
      normalized[section.to_s] = ordered if ordered.any?
    end
  rescue NoMethodError
    {}
  end

  def self.menu_order_for(profile, section)
    raw = profile.respond_to?(:permissions) ? profile.permissions : profile
    raw_hash = raw.respond_to?(:to_h) ? raw.to_h : {}
    normalize_menu_order(raw_hash[MENU_ORDER_PERMISSION_KEY] || raw_hash[MENU_ORDER_PERMISSION_KEY.to_sym])[section.to_s]
  end

  def self.permission_tree_sections(profile: nil)
    sections = SIDEBAR_SECTION_DEFINITIONS.map do |definition|
      resources = RESOURCES.select do |resource|
        permission_section_for_resource(resource) == definition.fetch(:key) &&
          (resource[:parent_section].blank? || section_resource?(resource[:parent_section]))
      end
      next if resources.empty?

      section_resource = resources.find { |resource| resource[:section] }
      ordered_resources = order_resources_like_sidebar(resources, definition.fetch(:key), profile: profile)
      {
        key: definition.fetch(:key),
        label: definition.fetch(:label),
        icon: definition.fetch(:icon),
        resource: section_resource,
        resources: ordered_resources.reject { |resource| resource[:key] == section_resource&.fetch(:key) }
      }
    end.compact

    internal_resources = RESOURCES.select { |resource| permission_section_for_resource(resource) == INTERNAL_PERMISSION_SECTION.fetch(:key) }
    if internal_resources.any?
      sections << INTERNAL_PERMISSION_SECTION.merge(resource: nil, resources: internal_resources)
    end

    sections
  end

  def self.order_resources_like_sidebar(resources, section, profile: nil)
    sidebar_order = sidebar_resource_order_for(section, profile: profile)
    resources.sort_by.with_index do |resource, index|
      sidebar_index = sidebar_order.index(resource.fetch(:key).to_s)
      [sidebar_index || sidebar_order.size + index, index]
    end
  end

  def self.permission_section_for_resource(resource)
    resource_key = resource.fetch(:key).to_s
    mapped = INTERNAL_PERMISSION_SECTION_BY_RESOURCE[resource_key]
    return mapped if mapped.present?
    return resource[:sidebar_section].to_sym if resource[:sidebar_section].present?

    parent = resource_for(resource[:parent_section])
    return parent[:sidebar_section].to_sym if parent&.dig(:sidebar_section).present?

    INTERNAL_PERMISSION_SECTION.fetch(:key)
  end

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
    permissions.deep_dup.tap { |payload| apply_habitation_field_lock_defaults!(payload) }
  end

  def self.apply_habitation_field_lock_defaults!(permissions)
    return permissions unless permissions.is_a?(Hash)

    imoveis = permissions["imoveis"]
    return permissions unless imoveis.is_a?(Hash)
    return permissions if imoveis["locked_fields"].is_a?(Array)

    full_access = permissions["admin"] == true || imoveis["scope"].to_s == "all"
    imoveis["locked_fields"] = full_access ? [] : Habitations::FieldLockPolicy.default_locked_keys.to_a
    permissions
  end

  def self.habitation_search_status_options_for(tenant)
    statuses = Habitation::STATUS_OPTIONS
    if tenant.present?
      statuses += tenant.habitations
        .where("NULLIF(TRIM(status), '') IS NOT NULL AND status != '.'")
        .distinct
        .pluck(:status)
    end

    statuses
      .map { |status| Habitation.normalize_status(status) }
      .compact_blank
      .uniq
      .sort_by { |status| I18n.transliterate(status).downcase }
  end

  def self.normalize_habitation_search_statuses(values, tenant:)
    available = habitation_search_status_options_for(tenant)
    normalized = Array(values)
      .flatten
      .map { |status| Habitation.normalize_status(status.to_s.squish) }
      .compact_blank
      .uniq

    normalized & available
  end

  # Pode fazer `action` sobre `resource`?
  # Ex: profile.can?(:view, :leads) / profile.can?("manage", "imoveis")
  def can?(action, resource)
    return true if admin? || full_access?
    permissions_hash.dig(resource.to_s, action.to_s) == true
  end

  def permission_configured?(resource)
    permissions_hash.key?(resource.to_s)
  end

  def permission_action_configured?(action, resource)
    entry = permissions_hash[resource.to_s]
    entry.is_a?(Hash) && entry.key?(action.to_s)
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
    configured = permissions_hash.dig(resource.to_s, "scope").presence_in(SCOPE_RANKS.keys)
    return nil if horizontal? && configured == "team"

    configured
  end

  def habitation_search_statuses_configured?
    permissions_hash.dig("imoveis", HABITATION_SEARCH_STATUSES_PERMISSION_KEY).is_a?(Array)
  end

  def habitation_search_statuses_for(tenant)
    available = self.class.habitation_search_status_options_for(tenant)
    return available if admin? || full_access?

    configured = permissions_hash.dig("imoveis", HABITATION_SEARCH_STATUSES_PERMISSION_KEY)
    return available unless configured.is_a?(Array)

    self.class.normalize_habitation_search_statuses(configured, tenant: tenant)
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

  def normalize_habitation_field_locks
    self.class.apply_habitation_field_lock_defaults!(permissions)
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
