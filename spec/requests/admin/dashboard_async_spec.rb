require "rails_helper"

RSpec.describe "Admin dashboard async slices", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza a visão geral sem carregar slices de outras áreas" do
    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visão geral", "Leads", "Imóveis", "Site público")
    expect(response.body).to include('aria-current="page"')
    document = Nokogiri::HTML(response.body)
    expect(document.css(".ax-dashboard-tabs__badge").size).to be >= 9
    expect(response.body).to include("Total geral de leads visíveis no escopo atual do dashboard.")
    expect(response.body).to include("Leads abertos que ainda não têm corretor responsável.")
    expect(response.body).to include("Tarefas vencidas em leads abertos do escopo atual.")
    expect(response.body).to include("Leads sem registro de primeiro contato há mais de 4 horas.")
    expect(response.body).to include("Total geral de imóveis ativos visíveis no escopo atual do dashboard.")
    expect(response.body).to include("Imóveis do catálogo operacional sem preço de venda e locação, excluindo empreendimentos.")
    expect(response.body).to include("Imóveis publicáveis sem atualização há mais de 90 dias.")
    expect(response.body).to include("Páginas públicas vistas no período, geradas pelo rastreamento próprio do site.")
    expect(response.body).to include("Aberturas reais de páginas de imóveis no site público.")
    expect(response.body).to include("Cliques reais em chamadas de WhatsApp capturados no site público.")
    expect(response.body).not_to include('id="admin_dashboard_charts"')
    expect(response.body).to include("Decisão operacional")
    expect(response.body).to include("IA textual")
    expect(response.body).to include("Diagnóstico da semana")
    expect(response.body).to include("determinístico")
    expect(response.body).to include("diagnóstico(s) IA na semana")
    expect(response.body).to include("Mapa de investigação operacional")
    expect(response.body).not_to include("Resumo operacional")
    expect(response.body).not_to include("Hoje e próximos passos")
    expect(response.body).not_to include("Imóveis no catálogo")
    expect(response.body).not_to include("Leads hoje")
    expect(response.body).not_to include("Regras de distribuição")
    expect(response.body).not_to include("Módulo Campo desativado")
  end

  it "redireciona acesso direto ao slice do site para o dashboard completo" do
    get admin_dashboard_section_path("site")

    expect(response).to redirect_to(admin_root_path(period: 30, tab: "site"))
  end

  it "responde perguntas operacionais com dados acionáveis na visão geral" do
    travel_to Time.zone.local(2026, 8, 8, 10, 0, 0) do
      tenant = Tenant.create!(name: "Tenant BI #{SecureRandom.hex(3)}", slug: "tenant-bi-#{SecureRandom.hex(3)}")
      owner = create(:admin_user, :admin, tenant: tenant)
      LeadSetting.instance(tenant: tenant).update!(first_contact_sla_hours: 6)
      sign_out admin
      sign_in owner

      property_lead = create(
        :lead,
        tenant: tenant,
        status: Lead.status_value(:novo),
        admin_user: nil,
        updated_at: 3.days.ago,
        created_at: 3.days.ago
      )
      create(
        :habitation,
        tenant: tenant,
        codigo: "dashboard-bi-sem-preco",
        imovel_dwv: "Sim",
        valor_venda_cents: 0,
        valor_locacao_cents: 0
      )
      property_with_demand = create(:habitation, tenant: tenant, codigo: "dashboard-bi-demanda", valor_venda_cents: 900_000_00)
      create(
        :lead,
        tenant: tenant,
        status: Lead.status_value(:novo),
        admin_user: owner,
        property_id: property_with_demand.id,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      ).tap do |lead_with_task|
        create(:task, tenant: tenant, lead: lead_with_task, admin_user: owner, title: "Retornar lead do painel", due_at: 1.hour.ago)
      end
      whatsapp_conversation = WhatsappConversation.create!(
        tenant: tenant,
        lead: property_lead,
        assigned_admin_user: owner,
        contact_phone: "5547999998800",
        contact_name: "Cliente WhatsApp BI",
        status: "open",
        unread_count: 1,
        last_message_at: 30.minutes.ago,
        last_message_preview: "Ainda tenho interesse"
      )
      WhatsappMessage.create!(
        tenant: tenant,
        whatsapp_conversation: whatsapp_conversation,
        direction: "outbound",
        body: "Olá, posso ajudar?",
        created_at: 2.hours.ago,
        updated_at: 2.hours.ago
      )
      WhatsappMessage.create!(
        tenant: tenant,
        whatsapp_conversation: whatsapp_conversation,
        direction: "inbound",
        body: "Ainda tenho interesse",
        created_at: 30.minutes.ago,
        updated_at: 30.minutes.ago
      )
      answered_whatsapp_conversation = WhatsappConversation.create!(
        tenant: tenant,
        assigned_admin_user: owner,
        contact_phone: "5547999998801",
        contact_name: "Cliente Respondido BI",
        status: "open",
        last_message_at: 20.minutes.ago,
        last_message_preview: "Obrigado"
      )
      WhatsappMessage.create!(
        tenant: tenant,
        whatsapp_conversation: answered_whatsapp_conversation,
        direction: "inbound",
        body: "Pode me chamar?",
        created_at: 80.minutes.ago,
        updated_at: 80.minutes.ago
      )
      WhatsappMessage.create!(
        tenant: tenant,
        whatsapp_conversation: answered_whatsapp_conversation,
        direction: "outbound",
        body: "Claro, vamos falar agora.",
        created_at: 20.minutes.ago,
        updated_at: 20.minutes.ago
      )

      get admin_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ações recomendadas")
      expect(response.body).to include("Por onde começar agora?")
      expect(response.body).to include("Atender leads sem primeiro contato")
      expect(response.body).to include("Resolver tarefas vencidas")
      expect(response.body).to include("attention_filter=task_overdue")
      expect(response.body).to include("attention_filter=no_first_contact")
      expect(response.body).to include("Responder WhatsApp pendente")
      expect(response.body).to include("WhatsApp está ficando sem retorno?")
      expect(response.body).to include("Cliente WhatsApp BI")
      expect(response.body).to include("Tempo médio de resposta")
      expect(response.body).to include("minutos nas conversas respondidas no período")
      expect(response.body).to include("/admin/atendimento/whatsapp?filter=pending_reply")
      expect(response.body).to include(admin_whatsapp_conversation_path(whatsapp_conversation))
      expect(response.body).to include("O atendimento está dentro do SLA?")
      expect(response.body).to include("SLA 6h vencido")
      expect(response.body).to include("Onde o funil está travando?")
      expect(response.body).to include("Quais imóveis têm demanda sem avanço?")
      expect(response.body).to include("dashboard-bi-demanda")
      expect(response.body).to include("property_q=dashboard-bi-demanda")
      expect(response.body).to include("O que exige ação agora?")
      expect(response.body).to include("Quem precisa agir agora?")
      expect(response.body).to include("/admin/leads?attention_filter=requires_action")
      expect(response.body).to include("sem responsável")
      expect(response.body).to include("tarefa(s) vencida(s)")
      expect(response.body).not_to include("Nenhuma pendência no momento.")
      expect(response.body).to include("Quem está segurando atendimento?")
      expect(response.body).to include("Sem responsável")
      expect(response.body).to include("broker_id=unassigned")
      expect(response.body).to include("Qual gargalo bloqueia publicação?")
      expect(response.body).to include("dashboard_quality=missing_price")
      expect(response.body).to include("Sem valor de venda/locação")
      expect(response.body).to include("De onde vem a demanda útil?")
      expect(response.body).to include("Direto / desconhecido")
      expect(response.body).to include("attribution_channel=direct")
      expect(response.body).to include("A carteira está pronta para vender?")
      expect(response.body).to include("principal gargalo: sem preço")
      expect(response.body).to include("Os leads estão sendo distribuídos?")
      expect(response.body).to include("Nenhuma regra de distribuição configurada.")
      expect(response.body).to include('data-turbo-frame="_top"')
    end
  end

  it "mantém o número do card de catálogo alinhado com o filtro principal" do
    travel_to Time.zone.local(2026, 8, 8, 10, 0, 0) do
      tenant = Tenant.create!(name: "Tenant catálogo BI #{SecureRandom.hex(3)}", slug: "tenant-catalogo-bi-#{SecureRandom.hex(3)}")
      owner = create(:admin_user, :admin, tenant: tenant)
      sign_out admin
      sign_in owner

      create(:habitation, tenant: tenant, codigo: "dashboard-stale-1", imovel_dwv: "Sim", data_atualizacao_crm: 100.days.ago)
      create(:habitation, tenant: tenant, codigo: "dashboard-stale-2", imovel_dwv: "Sim", data_atualizacao_crm: 95.days.ago)
      create(:habitation, tenant: tenant, codigo: "dashboard-sem-preco", imovel_dwv: "Sim", valor_venda_cents: 0, valor_locacao_cents: 0)
      create(:habitation, tenant: tenant, codigo: "dashboard-empreendimento-sem-preco", imovel_dwv: "Sim", tipo: "Empreendimento", valor_venda_cents: 0, valor_locacao_cents: 0)

      get admin_root_path

      document = Nokogiri::HTML(response.body)
      catalog_card = document.css(".ax-dashboard-question").find { |node| node.text.include?("A carteira está pronta para vender?") }

      expect(catalog_card.text).to include("2")
      expect(catalog_card.text).to include("principal gargalo: desatualizados há 90 dias")
      expect(catalog_card.text).to include("3 ponto(s) no total")
      expect(catalog_card["href"]).to include("dashboard_quality=stale")
    end
  end

  it "usa a mesma regra do filtro somente sem imagens para imóveis sem fotos" do
    tenant = Tenant.create!(name: "Tenant fotos BI #{SecureRandom.hex(3)}", slug: "tenant-fotos-bi-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, :admin, tenant: tenant)
    sign_out admin
    sign_in owner

    create(:habitation, tenant: tenant, codigo: "dashboard-sem-foto-1", pictures: [])
    create(:habitation, tenant: tenant, codigo: "dashboard-sem-foto-2", pictures: [])
    create(:habitation, tenant: tenant, codigo: "dashboard-sem-foto-pendente", status: "Pendente", exibir_no_site_flag: false, pictures: [])
    create(:habitation, tenant: tenant, codigo: "dashboard-com-picture-publica")

    get admin_dashboard_section_path("operations"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    missing_photos_card = document.css(".ax-dashboard-quality__item").find { |node| node.text.include?("Sem fotos") }

    expect(missing_photos_card.text).to include("3")
    expect(missing_photos_card["href"]).to include("ownership=all")
    expect(missing_photos_card["href"]).to include("somente_sem_imagens=1")

    get admin_habitations_path(ownership: "all", dashboard_quality: "missing_photos")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dashboard-sem-foto-1")
    expect(response.body).to include("dashboard-sem-foto-2")
    expect(response.body).to include("dashboard-sem-foto-pendente")
    expect(response.body).not_to include("dashboard-com-picture-publica")

    get admin_habitations_path(ownership: "all", somente_sem_imagens: "1")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dashboard-sem-foto-1")
    expect(response.body).to include("dashboard-sem-foto-2")
    expect(response.body).to include("dashboard-sem-foto-pendente")
    expect(response.body).not_to include("dashboard-com-picture-publica")
  end

  it "usa o catálogo operacional sem empreendimentos para imóveis sem preço" do
    tenant = Tenant.create!(name: "Tenant preço BI #{SecureRandom.hex(3)}", slug: "tenant-preco-bi-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, :admin, tenant: tenant)
    sign_out admin
    sign_in owner

    missing_price = create(:habitation, tenant: tenant, codigo: "dashboard-sem-preco-1", valor_venda_cents: 0, valor_locacao_cents: 0)
    internal_missing_price = create(:habitation, tenant: tenant, codigo: "dashboard-sem-preco-pendente", status: "Pendente", exibir_no_site_flag: false, valor_venda_cents: nil, valor_locacao_cents: nil)
    development = create(:habitation, tenant: tenant, codigo: "dashboard-empreendimento-sem-preco", tipo: "Empreendimento", valor_venda_cents: 0, valor_locacao_cents: 0)
    priced = create(:habitation, tenant: tenant, codigo: "dashboard-com-preco", valor_venda_cents: 900_000_00, valor_locacao_cents: 0)

    get admin_dashboard_section_path("operations"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    missing_price_card = document.css(".ax-dashboard-quality__item").find { |node| node.text.include?("Sem preço") }

    expect(missing_price_card.text).to include("2")
    expect(missing_price_card.text).to include("Sem valor de venda/locação")
    expect(missing_price_card.text).to include("1 empreendimento(s) fora do alerta")
    expect(missing_price_card["href"]).to include("ownership=all")
    expect(missing_price_card["href"]).to include("dashboard_quality=missing_price")

    get admin_habitations_path(ownership: "all", dashboard_quality: "missing_price")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(missing_price.codigo)
    expect(response.body).to include(internal_missing_price.codigo)
    expect(response.body).not_to include(development.codigo)
    expect(response.body).not_to include(priced.codigo)
  end

  it "aplica os filtros operacionais usados pelos cards do BI na lista de leads" do
    travel_to Time.zone.local(2026, 8, 8, 10, 0, 0) do
      tenant = Tenant.create!(name: "Tenant filtros BI #{SecureRandom.hex(3)}", slug: "tenant-filtros-bi-#{SecureRandom.hex(3)}")
      owner = create(:admin_user, :admin, tenant: tenant)
      broker = owner
      LeadSetting.instance(tenant: tenant).update!(first_contact_sla_hours: 36)
      sign_out admin
      sign_in owner

      stale_without_contact = create(:lead, tenant: tenant, name: "Lead sem primeiro contato BI", status: Lead.status_value(:novo), admin_user: broker, created_at: 2.days.ago, updated_at: 3.days.ago, attribution_channel: "meta_ads")
      overdue_task_lead = create(:lead, tenant: tenant, name: "Lead com tarefa vencida BI", status: Lead.status_value(:em_atendimento), admin_user: broker, created_at: 1.day.ago, updated_at: 1.hour.ago, attribution_channel: "meta_ads")
      within_custom_sla = create(:lead, tenant: tenant, name: "Lead dentro SLA custom", status: Lead.status_value(:novo), admin_user: broker, created_at: 30.hours.ago, updated_at: 2.hours.ago, attribution_channel: "meta_ads")
      create(:lead, tenant: tenant, name: "Lead direto BI", status: Lead.status_value(:novo), admin_user: nil, updated_at: 1.hour.ago, attribution_channel: nil)
      contacted = create(:lead, tenant: tenant, name: "Lead ok BI", status: Lead.status_value(:novo), admin_user: broker, created_at: 2.hours.ago, updated_at: 1.hour.ago, attribution_channel: "google_ads")
      opportunity = create(:lead, tenant: tenant, name: "Lead com visita BI", status: Lead.status_value(:em_atendimento), admin_user: broker, created_at: 1.day.ago, updated_at: 1.hour.ago, attribution_channel: "google_ads")
      LeadActivity.create!(lead: contacted, kind: "whatsapp_out", created_at: 90.minutes.ago, updated_at: 90.minutes.ago)
      create(:task, tenant: tenant, lead: overdue_task_lead, admin_user: broker, title: "Retornar cliente do filtro", due_at: 1.hour.ago)
      Appointment.create!(tenant: tenant, lead: opportunity, admin_user: broker, title: "Visita oportunidade", kind: "visita", starts_at: 1.day.from_now, status: "agendado")

      get admin_leads_path(attention_filter: "requires_action")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead com tarefa vencida BI")
      expect(response.body).not_to include("Lead dentro SLA custom")
      expect(response.body).not_to include("Lead ok BI")
      expect(response.body).to include("Atenção operacional")

      get admin_leads_path(attention_filter: "task_overdue")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead com tarefa vencida BI")
      expect(response.body).not_to include("Lead sem primeiro contato BI")

      get admin_leads_path(attribution_channel: "direct", start_date: Date.current.iso8601, end_date: Date.current.iso8601)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead direto BI")
      expect(response.body).not_to include("Lead sem primeiro contato BI")
      expect(response.body).to include("Canal")

      get admin_leads_path(attention_filter: "no_first_contact")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atenção operacional")

      get admin_leads_path(attention_filter: "sla_overdue")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atenção operacional")

      get admin_leads_path(attention_filter: "with_opportunity")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(opportunity.name)
      expect(response.body).not_to include(stale_without_contact.name)
    end
  end

  it "permite dashboard principal para usuário operacional com permissão dashboard" do
    tenant = Tenant.create!(name: "Tenant dashboard #{SecureRandom.hex(3)}", slug: "tenant-dashboard-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Analista dashboard #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "dashboard" => { "view" => true },
        "imoveis" => { "view" => true, "scope" => "own" },
        "leads" => { "view" => true, "scope" => "own" },
        "captacoes" => { "view" => true, "scope" => "own" }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visão geral", "Leads", "Imóveis", "Site público")
    expect(response.body).not_to include(admin_profiles_path)
  end

  it "mantém usuário desktop sem permissão no workspace administrativo" do
    tenant = Tenant.create!(name: "Tenant sem dashboard #{SecureRandom.hex(3)}", slug: "tenant-sem-dashboard-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Sem dashboard #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "imoveis" => { "view" => true, "scope" => "own" }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visão geral", "Leads", "Imóveis")
  end

  it "carrega somente os painéis da aba Leads e preserva os filtros na URL" do
    get admin_root_path(tab: "leads", period: 7)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css(".ax-dashboard-skeleton")).not_to be_empty
    expect(document.css(".ax-skeleton-chart span").size).to eq(21)
    expect(document.css(".ax-skeleton-row b[class^='ax-skeleton-row__line--']")).not_to be_empty
    expect(document.css(".ax-dashboard-skeleton [style]")).to be_empty
    expect(document.css(".ax-dashboard-skeleton[role='status'][aria-live='polite'][aria-busy='true']")).not_to be_empty
    expect(document.css(".ax-skeleton-chart[aria-hidden='true'], .ax-skeleton-table[aria-hidden='true'], .ax-skeleton-list[aria-hidden='true']")).not_to be_empty
    expect(document.css(".ax-dashboard-skeleton").all? { |panel| panel["aria-label"].to_s.start_with?("Carregando ") }).to be(true)
    expect(document.css(".ax-dashboard-grid--lead-top").size).to eq(1)
    expect(response.body).to include('id="admin_dashboard_charts"')
    expect(response.body).to include('id="admin_dashboard_funnel"')
    expect(response.body).to include('id="admin_dashboard_status"')
    expect(response.body).to include('id="admin_dashboard_acquisition"')
    expect(response.body).to include('id="admin_dashboard_service"')
    expect(response.body).to include('id="admin_dashboard_rankings"')
    expect(response.body).to include("Performance e gargalo por corretor")
    expect(response.body).not_to include('aria-label="Carregando Performance e gargalo por corretor"')
    expect(response.body).to include("tab=leads")
    expect(response.body).to include("period=7")
    expect(response.body).not_to include('id="admin_dashboard_operations"')
    expect(response.body).not_to include('id="admin_dashboard_support"')
    expect(response.body).not_to include("Atenção necessária")
  end

  it "separa os painéis de Imóveis" do
    get admin_root_path(tab: "properties")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css(".ax-dashboard-properties-top > turbo-frame").size).to eq(2)
    expect(document.at_css(".ax-dashboard-properties-top--stacked > turbo-frame")[:id]).to eq("admin_dashboard_operations")
    expect(response.body).to include('id="admin_dashboard_rankings"')
    expect(response.body).to include('id="admin_dashboard_operations"')
    expect(response.body).to include('id="admin_dashboard_support"')
    expect(response.body).not_to include('id="admin_dashboard_charts"')
  end

  it "não renderiza painel vazio de captação na aba Imóveis" do
    tenant = Tenant.create!(name: "Tenant sem captação #{SecureRandom.hex(3)}", slug: "tenant-sem-captacao-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, :admin, tenant: tenant)
    sign_out admin
    sign_in owner
    create(:habitation, tenant: tenant, categoria: "Apartamento")

    get admin_dashboard_section_path("support", tab: "properties"), headers: { "Turbo-Frame" => "admin_dashboard_support" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Últimas captações")
    expect(response.body).not_to include("Nenhuma captação registrada ainda.")
    expect(response.body).to include("Distribuição por categoria")
    expect(response.body).to include("ax-dashboard-grid--support-single")
  end

  it "separa os painéis do Site público com dados reais por tenant" do
    travel_to Time.zone.local(2026, 8, 8, 10, 0, 0) do
      tenant = admin.tenant
      other_tenant = Tenant.create!(name: "Outro site #{SecureRandom.hex(3)}", slug: "outro-site-#{SecureRandom.hex(3)}")
      property = create(:habitation, tenant: tenant, codigo: "site-bi-101", titulo_anuncio: "Apartamento com vista")
      other_property = create(:habitation, tenant: other_tenant, codigo: "site-bi-outro")
      session = PublicNavigationSession.create!(tenant: tenant, token: SecureRandom.uuid)
      search_only_session = PublicNavigationSession.create!(tenant: tenant, token: SecureRandom.uuid)
      other_session = PublicNavigationSession.create!(tenant: other_tenant, token: SecureRandom.uuid)

      PublicNavigationEvent.create!(tenant: tenant, public_navigation_session: session, name: "page_view", path: "/")
      PublicNavigationEvent.create!(tenant: tenant, public_navigation_session: session, habitation: property, name: "property_view", path: "/imoveis/#{property.codigo}")
      PublicNavigationEvent.create!(tenant: tenant, public_navigation_session: session, habitation: property, name: "property_whatsapp_click", path: "/imoveis/#{property.codigo}")
      PublicNavigationEvent.create!(tenant: tenant, public_navigation_session: session, name: "property_search", path: "/imoveis", search_params: { "cidade" => "Balneário Camboriú", "transaction_type" => "venda" })
      PublicNavigationEvent.create!(tenant: tenant, public_navigation_session: session, name: "home_section_click", path: "/", metadata: { "home_section_id" => "7", "home_section_title" => "Destaques da home", "home_section_type" => "featured_properties" })
      PublicNavigationEvent.create!(tenant: tenant, public_navigation_session: search_only_session, name: "page_view", path: "/")
      PublicNavigationEvent.create!(tenant: tenant, public_navigation_session: search_only_session, name: "property_search", path: "/imoveis", search_params: { "cidade" => "Itajaí" })
      PublicNavigationEvent.create!(tenant: other_tenant, public_navigation_session: other_session, habitation: other_property, name: "property_view", path: "/imoveis/#{other_property.codigo}")

      get admin_root_path(tab: "site", period: 30)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="admin_dashboard_site"')
      expect(response.body).not_to include('id="admin_dashboard_charts"')

      get admin_dashboard_section_path("site", tab: "site", period: 30), headers: { "Turbo-Frame" => "admin_dashboard_site" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("O site está gerando intenção?")
      expect(response.body).to include("2</strong>")
      expect(response.body).to include("visitas")
      expect(response.body).to include("imóveis vistos")
      expect(response.body).to include("ações de contato")
      expect(response.body).to include("Onde o visitante avança ou abandona?")
      expect(response.body).to include("Listagem/busca")
      expect(response.body).to include("50% da etapa anterior")
      expect(response.body).to include("Quais seções recebem cliques?")
      expect(response.body).to include("Destaques da home")
      expect(response.body).to include("Imóveis em Destaque")
      expect(response.body).to include("/imoveis/#{property.codigo}")
      expect(response.body).to include("site-bi-101")
      expect(response.body).to include("Cidade: Balneário Camboriú")
      expect(response.body).not_to include("site-bi-outro")
    end
  end

  it "mantém a aba Site público enxuta quando ainda não há eventos reais" do
    get admin_dashboard_section_path("site", tab: "site", period: 30), headers: { "Turbo-Frame" => "admin_dashboard_site" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ainda não há eventos públicos reais no período")
    expect(response.body).not_to include("Onde o visitante avança ou abandona?")
    expect(response.body).not_to include("Quais páginas puxam atenção?")
    expect(response.body).not_to include("O que o visitante procura?")
  end

  it "faz os painéis filtrados de Imóveis ocuparem toda a coluna disponível" do
    get admin_dashboard_section_path("rankings", tab: "properties"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }
    expect(response.body).to include("ax-dashboard-grid--rankings-single")

    get admin_dashboard_section_path("operations", tab: "properties"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }
    expect(response.body).to include("ax-dashboard-grid--single")
  end

  it "oculta Campo quando o módulo está pausado e volta para a visão geral" do
    allow(FieldFeatureGate).to receive(:field_checkin_enabled?).and_return(false)
    store = create(:store, tenant: admin.tenant)
    agent = create(:admin_user, :field_agent, tenant: admin.tenant)
    create(:manual_checkin_request, tenant: admin.tenant, admin_user: agent, store: store)

    get admin_root_path(tab: "field")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('<span class="ax-dashboard-tabs__label">Campo</span>')
    expect(response.body).to include("Campo pausado")
    expect(response.body).to include("Decisão operacional")
    expect(response.body).not_to include("Pedidos manuais pendentes")
    expect(response.body).not_to include('id="admin_dashboard_operations"')
  end
  it "exibe os painéis de Campo quando o módulo está ativo" do
    allow(FieldFeatureGate).to receive(:field_checkin_enabled?).and_return(true)

    get admin_root_path(tab: "field")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<span class="ax-dashboard-tabs__label">Campo</span>')
    expect(response.body).to include('id="admin_dashboard_rankings"')
    expect(response.body).to include('id="admin_dashboard_operations"')
    expect(response.body).not_to include('id="admin_dashboard_support"')
  end

  it "não mistura domínios dentro dos slices compartilhados" do
    allow(FieldFeatureGate).to receive(:field_checkin_enabled?).and_return(true)

    get admin_dashboard_section_path("rankings", tab: "leads"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }
    expect(response.body).to include("Performance e gargalo por corretor")
    expect(response.body).not_to include("Carteira de imóveis por corretor", "Top lojas por check-ins")

    get admin_dashboard_section_path("rankings", tab: "properties"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }
    expect(response.body).to include("Carteira de imóveis por corretor")
    expect(response.body).not_to include("Performance e gargalo por corretor", "Top lojas por check-ins")

    get admin_dashboard_section_path("operations", tab: "field"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }
    expect(response.body).to include("Atividade recente")
    expect(response.body).not_to include("Últimos imóveis atualizados")
  end

  it "direciona usuário mobile sem permissão de dashboard para o Field" do
    tenant = Tenant.create!(name: "Tenant mobile #{SecureRandom.hex(3)}", slug: "tenant-mobile-#{SecureRandom.hex(3)}")
    profile = Profile.create!(tenant: tenant, name: "Field mobile #{SecureRandom.hex(3)}", axis: "vertical", position: 601, permissions: {})
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in user
    get admin_root_path, headers: { "User-Agent" => "Mozilla/5.0 (Linux; Android 15) Mobile" }

    expect(response).to redirect_to(field_root_path)
  end

  it "renderiza cada slice em seu turbo frame" do
    %w[charts acquisition funnel status service rankings operations support site].each do |section|
      get admin_dashboard_section_path(section), headers: { "Turbo-Frame" => "admin_dashboard_#{section}" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="admin_dashboard_#{section}"))
    end
  end

  it "mostra atendimento e WhatsApp na aba de Leads com links filtrados" do
    travel_to Time.zone.local(2026, 8, 8, 10, 0, 0) do
      lead = create(:lead, tenant: admin.tenant, admin_user: nil, status: Lead.status_value(:novo), created_at: 6.hours.ago, updated_at: 5.hours.ago)
      conversation = WhatsappConversation.create!(tenant: admin.tenant, lead: lead, contact_phone: "5547999996600", contact_name: "Cliente SLA", status: "open", unread_count: 1)
      conversation.messages.create!(tenant: admin.tenant, direction: "inbound", body: "Ainda está disponível?", created_at: 30.minutes.ago, updated_at: 30.minutes.ago)
      template = WhatsappTemplate.create!(tenant: admin.tenant, name: "campanha_bi", language: "pt_BR", status: "APPROVED", body: "Oi {{1}}")
      sender_number = create(:whatsapp_sender_number, tenant: admin.tenant)
      campaign = WhatsappCampaign.create!(
        tenant: admin.tenant,
        whatsapp_template: template,
        whatsapp_sender_number: sender_number,
        created_by: admin,
        name: "Campanha BI",
        status: "completed",
        total_recipients: 2,
        sent_count: 1,
        failed_count: 1,
        replied_count: 1
      )
      WhatsappCampaignMessage.create!(tenant: admin.tenant, whatsapp_campaign: campaign, phone_number: "5547999996610", status: "replied", replied_at: 20.minutes.ago)
      handled_reply = WhatsappCampaignMessage.create!(tenant: admin.tenant, whatsapp_campaign: campaign, phone_number: "5547999996613", status: "replied", replied_at: 30.minutes.ago)
      handled_conversation = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: handled_reply.phone_number, contact_name: "Cliente tratado", status: "open")
      handled_conversation.messages.create!(tenant: admin.tenant, direction: "outbound", body: "Vou te chamar agora.", created_at: 10.minutes.ago, updated_at: 10.minutes.ago)
      WhatsappCampaignMessage.create!(tenant: admin.tenant, whatsapp_campaign: campaign, phone_number: "5547999996611", status: "failed", failed_at: 15.minutes.ago, failure_reason: "Erro Meta")
      create(:whatsapp_campaign_unsubscribe, tenant: admin.tenant, whatsapp_sender_number: sender_number, whatsapp_campaign: campaign, phone_number: "5547999996612")
      create(:task, tenant: admin.tenant, lead: lead, admin_user: admin, title: "Retornar cliente SLA", due_at: 1.hour.ago)

      get admin_dashboard_section_path("service"), headers: { "Turbo-Frame" => "admin_dashboard_service" }

      expect(response).to have_http_status(:ok)

      expect(response.body).to include("Atendimento e próximas ações")
      expect(response.body).to include("Tarefas vencidas")
      expect(response.body).to include("attention_filter=task_overdue")
      expect(response.body).to include("Sem primeiro contato")
      expect(response.body).to include("attention_filter=no_first_contact")
      expect(response.body).to include("SLA 4h vencido")
      expect(response.body).to include("attention_filter=sla_overdue")
      expect(response.body).to include("Atendimento pelo inbox")
      expect(response.body).to include("Aguardando resposta")
      expect(response.body).to include("filter=pending_reply")
      expect(response.body).to include("Não lidas")
      expect(response.body).to include("filter=unread")
      expect(response.body).to include("Disparos e retornos")
      expect(response.body).to include("Campanhas com retorno")
      expect(response.body).to include("Falhas de disparo")
      expect(response.body).to include("Descadastros")
      expect(response.body).to include("Respostas não tratadas")
      expect(response.body).to include("status=failed")
      document = Nokogiri::HTML(response.body)
      campaign_return = document.css(".ax-dashboard-service-row").find { |node| node.text.include?("Campanhas com retorno") }
      unhandled_reply = document.css(".ax-dashboard-service-row").find { |node| node.text.include?("Respostas não tratadas") }
      expect(campaign_return.text).to include("1")
      expect(unhandled_reply.text).to include("1")
    end
  end

  it "resume aquisição e campanhas pagas no período" do
    meta_lead = create(:lead, tenant: admin.tenant, admin_user: admin, attribution_channel: "meta_ads", attribution_data: { "utm_campaign" => "verao", "utm_id" => "123" }, created_at: 2.days.ago)
    create(:lead, tenant: admin.tenant, admin_user: admin, attribution_channel: "meta_ads", attribution_data: { "utm_campaign" => "verao" }, created_at: 1.day.ago)
    create(:lead, tenant: admin.tenant, attribution_channel: "direct", attribution_data: {}, created_at: 2.days.ago)
    property = create(:habitation, tenant: admin.tenant, codigo: "money-loss-101", titulo_anuncio: "Apartamento sem evolução")
    create(:lead, tenant: admin.tenant, property_id: property.id, attribution_channel: "meta_ads", created_at: 1.day.ago)
    create(:lead, tenant: admin.tenant, property_id: property.id, attribution_channel: "google_ads", created_at: 1.day.ago)
    MarketingCampaign.create!(tenant: admin.tenant, name: "Campanha cara sem retorno", channel: "meta_ads", status: "active", budget_cents: 1_500_00, conversions_count: 0, starts_on: 1.day.ago.to_date)
    Appointment.create!(tenant: admin.tenant, lead: meta_lead, admin_user: admin, title: "Visita BI", kind: "visita", starts_at: 1.day.from_now, status: "agendado")
    Proposal.create!(lead: meta_lead, admin_user: admin, status: "enviada", title: "Proposta BI")

    get admin_dashboard_section_path("acquisition", period: 7), headers: { "Turbo-Frame" => "admin_dashboard_acquisition" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Origem dos leads")
    expect(response.body).to include("Taxa de atribuição")
    expect(response.body).to include("Meta Ads")
    expect(response.body).to include("verao")
    expect(response.body).to include("ID 123")
    expect(response.body).to include("ax-dashboard-campaign-grid")
    expect(response.body).to include("ax-dashboard-campaign-row__count")
    expect(response.body).to include("Qual canal está gerando oportunidade?")
    expect(response.body).to include("Avanço considera leads que chegaram a visita, proposta ou conclusão")
    expect(response.body).to include("visitas")
    expect(response.body).to include("propostas")
    expect(response.body).to include("Onde pode estar vazando dinheiro?")
    expect(response.body).to include("Leads pagos sem atendimento")
    expect(response.body).to include("Canal caro com baixa conversão")
    expect(response.body).to include("Campanha com custo e pouco retorno")
    expect(response.body).to include("Campanha cara sem retorno")
    expect(response.body).to include("Imóvel com interesse sem evolução")
    expect(response.body).to include("money-loss-101")
  end

  it "expõe indicadores acionáveis de qualidade do catálogo" do
    property = create(:habitation, tenant: admin.tenant, codigo: "ops-interest-101", titulo_anuncio: "Imóvel com procura")
    create(:lead, tenant: admin.tenant, property_id: property.id, created_at: 1.day.ago)
    create(:lead, tenant: admin.tenant, property_id: property.id, created_at: 1.day.ago)
    session = PublicNavigationSession.create!(tenant: admin.tenant, token: SecureRandom.uuid)
    PublicNavigationEvent.create!(tenant: admin.tenant, public_navigation_session: session, habitation: property, name: "property_view", path: "/imoveis/#{property.codigo}", occurred_at: 1.day.ago)

    get admin_dashboard_section_path("operations"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Qualidade da publicação")
    expect(response.body).to include("Sem endereço")
    expect(response.body).to include("Sem fotos")
    expect(response.body).to include("Sem preço")
    expect(response.body).to include("Desatualizados há 90 dias")
    expect(response.body).to include("dashboard_quality=missing_address")
    expect(response.body).to include("Interesse alto e baixa evolução")
    expect(response.body).to include("ops-interest-101")
    expect(response.body).to include('data-turbo-frame="_top"')
  end

  it "usa o slug real da Habitation para abrir captações em rascunho fora do Turbo Frame" do
    intake = create(
      :habitation,
      :broker_intake,
      tenant: admin.tenant,
      admin_user: admin,
      codigo: "dashboard-intake-draft",
      intake_status: "draft"
    )

    get admin_dashboard_section_path("support"), headers: { "Turbo-Frame" => "admin_dashboard_support" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML(edit_admin_captacao_path(intake)))
    expect(response.body).not_to include(CGI.escapeHTML(edit_admin_captacao_path(intake.id))) unless intake.to_param == intake.id.to_s
    expect(response.body).to include('data-turbo-frame="_top"')
  end

  it "filtra o catálogo pelo indicador de qualidade selecionado" do
    tenant = Tenant.create!(name: "Tenant filtro preço #{SecureRandom.hex(3)}", slug: "tenant-filtro-preco-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, :admin, tenant: tenant)
    sign_out admin
    sign_in owner

    missing_price = create(:habitation, tenant: tenant, codigo: "dashboard-missing-price", valor_venda_cents: 0, valor_locacao_cents: 0)
    internal_missing_price = create(:habitation, tenant: tenant, codigo: "dashboard-internal-missing-price", status: "Pendente", exibir_no_site_flag: false, valor_venda_cents: nil, valor_locacao_cents: nil)
    development = create(:habitation, tenant: tenant, codigo: "dashboard-development-without-price", tipo: "Empreendimento", valor_venda_cents: 0, valor_locacao_cents: 0)
    priced = create(:habitation, tenant: tenant, codigo: "dashboard-priced", valor_venda_cents: 900_000_00, valor_locacao_cents: 0)

    get admin_habitations_path(ownership: "all", dashboard_quality: "missing_price")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(missing_price.codigo)
    expect(response.body).to include(internal_missing_price.codigo)
    expect(response.body).not_to include(development.codigo)
    expect(response.body).not_to include(priced.codigo)
  end

  it "inclui o funil comercial em slice dedicado" do
    lead = create(:lead, tenant: admin.tenant, status: Lead.status_value(:em_atendimento), created_at: 3.days.ago, updated_at: 3.days.ago)
    hot_lead = create(:lead, tenant: admin.tenant, status: Lead.status_value(:em_atendimento), tags: ["quente"], created_at: 3.days.ago, updated_at: 2.days.ago)
    warm_lead = create(:lead, tenant: admin.tenant, status: Lead.status_value(:novo), tags: ["morno"], created_at: 5.days.ago, updated_at: 4.days.ago)
    LeadAuditLog.create!(
      tenant: admin.tenant,
      lead: lead,
      action: "status_changed",
      source: "admin",
      changed_fields: ["status"],
      changeset: { "status" => { "before" => Lead.status_value(:em_atendimento), "after" => Lead.status_value(:descartado) } },
      created_at: 1.day.ago
    )
    LeadAuditLog.create!(
      tenant: admin.tenant,
      lead: hot_lead,
      action: "status_changed",
      source: "admin",
      changed_fields: ["status"],
      changeset: { "status" => { "before" => Lead.status_value(:descartado), "after" => Lead.status_value(:em_atendimento) } },
      created_at: 12.hours.ago
    )

    get admin_dashboard_section_path("funnel"), headers: { "Turbo-Frame" => "admin_dashboard_funnel" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conversão comercial")
    expect(response.body).to include("Clientes impactados")
    expect(response.body).to include("Leads interessados")
    expect(response.body).to include("Oportunidades")
    expect(response.body).to include("Vendas")
    expect(response.body).to include("Referência:")
    expect(response.body).to include("ax-dashboard-funnel-layout")
    expect(response.body).to include("Tempo médio em cada etapa")
    expect(response.body).to include("Perdas e reaberturas")
    expect(response.body).to include("Leads quentes/mornos sem ação")
    expect(response.body).to include("Leads quentes sem ação")
    expect(response.body).to include("Leads mornos sem ação")
    expect(response.body).to include("voltaram")
    expect(response.body).to include("%")
    expect(Nokogiri::HTML(response.body).css(".ax-dashboard-funnel [style]")).to be_empty
  end

  it "nomeia o ranking como distribuição de carteira e oculta Campo quando pausado" do
    allow(FieldFeatureGate).to receive(:field_checkin_enabled?).and_return(false)

    get admin_dashboard_section_path("rankings"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Carteira de imóveis por corretor")
    expect(response.body).not_to include("Top corretores por imóveis")
    expect(response.body).not_to include("Top lojas por check-ins")
  end

  it "inclui a pizza de status em slice dedicado" do
    get admin_dashboard_section_path("status"), headers: { "Turbo-Frame" => "admin_dashboard_status" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Leads por status")
    expect(response.body).to include("leadsStatusChart")
    expect(response.body).to include("Abrir leads por status")
  end

  it "mantém a visão geral focada em decisão e investigação" do
    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Decisão operacional")
    expect(response.body).to include("Mapa de investigação operacional")
    expect(response.body).not_to include("Ver imóveis no catálogo")
    expect(response.body).not_to include("Ver leads recebidos hoje")
    expect(response.body).not_to include("Ver regras de distribuição")
    expect(response.body).not_to include("Resumo operacional")
    expect(response.body).not_to include("Hoje e próximos passos")
  end

  it "propaga período e corretor para os slices do dashboard" do
    broker = create(:admin_user, tenant: admin.tenant)

    get admin_root_path(period: 7, broker_id: broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Escopo do painel")
    expect(response.body).to include("period=7")
    expect(response.body).to include("broker_id=#{broker.id}")
  end

  it "renderiza desempenho comercial no período selecionado" do
    broker = create(:admin_user, tenant: admin.tenant)
    lead = create(:lead, tenant: admin.tenant, admin_user: broker, status: "Concluido", created_at: 2.days.ago)
    create(:lead, tenant: admin.tenant, admin_user: broker, status: Lead.status_value(:novo), created_at: 4.days.ago, updated_at: 3.days.ago)
    Appointment.create!(tenant: admin.tenant, lead: lead, admin_user: broker, title: "Visita realizada", kind: "visita", starts_at: 1.day.ago, status: "realizado")
    Proposal.create!(lead: lead, admin_user: broker, status: "enviada", title: "Proposta enviada")

    get admin_dashboard_section_path("rankings", period: 7), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Performance e gargalo por corretor")
    expect(response.body).to include(broker.name)
    expect(response.body).to include("visitas")
    expect(response.body).to include("propostas")
    expect(response.body).to include("concluídos")
    expect(response.body).to include("avanço")
    expect(response.body).to include("agir")
    expect(response.body).to include("attention_filter=requires_action")
  end

  it "renderiza oferta versus demanda usando leads vinculados a imóveis" do
    habitation = create(:habitation, tenant: admin.tenant, categoria: "Apartamento", codigo: "DASH-#{SecureRandom.hex(5)}")
    create(:lead, tenant: admin.tenant, property_id: habitation.id, created_at: 2.days.ago)

    get admin_dashboard_section_path("support", period: 7), headers: { "Turbo-Frame" => "admin_dashboard_support" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Oferta versus demanda por categoria")
    expect(response.body).to include("Apartamento")
    expect(response.body).to include("Leads vinculados")
    expect(Nokogiri::HTML(response.body).css("progress.ax-progress__bar")).not_to be_empty
  end

  it "gera a serie de leads dos ultimos 30 dias incluindo o dia atual" do
    isolated_tenant = Tenant.create!(name: "Tenant dashboard serie #{SecureRandom.hex(3)}", slug: "tenant-dashboard-serie-#{SecureRandom.hex(3)}")
    isolated_admin = create(:admin_user, :admin, tenant: isolated_tenant)
    sign_out admin
    sign_in isolated_admin

    travel_to Time.zone.local(2026, 6, 16, 10, 0, 0) do
      create(:lead, tenant: isolated_tenant, created_at: Time.zone.local(2026, 6, 16, 9, 0, 0))
      create(:lead, tenant: isolated_tenant, created_at: Time.zone.local(2026, 5, 18, 9, 0, 0))
      create(:lead, tenant: isolated_tenant, created_at: Time.zone.local(2026, 5, 17, 9, 0, 0))

      get admin_dashboard_section_path("charts"), headers: { "Turbo-Frame" => "admin_dashboard_charts" }
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("&quot;2026-05-18&quot;")
    expect(response.body).to include("&quot;2026-06-16&quot;")
    expect(response.body).not_to include("&quot;2026-05-17&quot;")
    expect(response.body).to include("2 total")
  end

  it "permite selecionar um dia e agrupa as conversões pela hora de entrada do lead" do
    travel_to Time.zone.local(2026, 6, 16, 18, 0, 0) do
      create(:lead, created_at: Time.zone.local(2026, 6, 15, 9, 10, 0))
      create(:lead, created_at: Time.zone.local(2026, 6, 15, 9, 55, 0))
      create(:lead, created_at: Time.zone.local(2026, 6, 15, 17, 20, 0))
      create(:lead, created_at: Time.zone.local(2026, 6, 16, 9, 0, 0))

      get admin_dashboard_section_path("charts", lead_date: "2026-06-15"),
          headers: { "Turbo-Frame" => "admin_dashboard_charts" }
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Leads por hora")
    expect(response.body).to include("3 total")
    expect(response.body).to include("&quot;09h&quot;,2")
    expect(response.body).to include("&quot;17h&quot;,1")
    expect(response.body).to include('data-dashboard-charts-leads-mode-value="hourly"')
    expect(response.body).to include('type="date"')
    expect(response.body).to include('value="2026-06-15"')
    expect(response.body).to include("30 dias")
  end

  it "ignora data horária fora da janela de 30 dias" do
    get admin_dashboard_section_path("charts", lead_date: 31.days.ago.to_date.iso8601),
        headers: { "Turbo-Frame" => "admin_dashboard_charts" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Leads — últimos 30 dias")
    expect(response.body).to include('data-dashboard-charts-leads-mode-value="daily"')
  end
end
