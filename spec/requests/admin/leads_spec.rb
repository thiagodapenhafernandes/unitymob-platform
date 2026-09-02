require "rails_helper"

RSpec.describe "Admin::Leads", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:admin_user, :admin, email: "leads-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET /admin/leads" do
    it "exibe o kanban como visualizacao padrao" do
      create(:lead, name: "Cliente Kanban", phone: "11999999999", status: "Novo")
      create(:lead, name: "Cliente Atendimento", phone: "11888888888", status: "Em Atendimento")

      get admin_leads_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lead-kanban")
      expect(response.body).to include("ax-leads-mobile-shell")
      expect(response.body).to include("lead-desktop-header")
      expect(response.body).to include("ax-leads-mobile-filter-button")
      expect(response.body).to include("Divergência")
      expect(response.body).to include("qualification_divergence")
      expect(response.body).to include("admin-push-banner")
      expect(response.body).to include("Filtros do funil")
      document = Nokogiri::HTML(response.body)
      expect(document.css("section.ax-filter-form.ax-leads-filters").size).to eq(1)
      expect(document.at_css("details.lead-filter-collapse")).to be_nil
      desktop_header = document.at_css(".lead-desktop-header")
      expect(desktop_header).to be_present
      expect(desktop_header.to_html).to include("A fazer", "Visitas", "Futuras", "Favoritos", "Todos")
      expect(document.at_css('button[data-ax-modal-open="#leadDesktopFilterModal"]')).to be_present
      filter_modal = document.at_css("#leadDesktopFilterModal")
      expect(filter_modal).to be_present
      expect(filter_modal.to_html).to include("Tipo de negociação", "Status", "Situação", "Canal", "Fonte", "Atividade")
      expect(filter_modal.to_html).to include("Motivo de arquivamento", "Etapa de funil")
      expect(filter_modal.to_html).not_to include("Vetra")
      expect(document.at_css('button[data-ax-modal-open="#leadPipelineCreateModal"]')).to be_present
      expect(document.at_css('button[data-ax-modal-open="#leadStatusBoardModal"]')).to be_present
      expect(document.at_css('a.ax-nav__link[href="/admin/leads?view=list"]')).to be_present
      expect(document.at_css(".ax-nav__link--group").text).to include("Funil")
      expect(document.at_css("#leadPipelineCreateModal.ax-quick-modal--lg")).to be_present
      expect(document.at_css("#leadStatusBoardModal.ax-quick-modal--fullscreen")).to be_present
      expect(document.at_css("#leadStatusBoardModal").to_html).not_to include("Criar novo funil")
      create_modal_html = document.at_css("#leadPipelineCreateModal").to_html
      edit_modal_html = document.at_css("#leadStatusBoardModal").to_html
      expect(create_modal_html).to include("stages[0][name]", "Negócio fechado")
      expect(create_modal_html).not_to include("Defaults")
      expect(edit_modal_html).not_to include("Defaults")
      expect(edit_modal_html).not_to include("Funil em edição")
      expect(edit_modal_html).to include("Auditoria")
      expect(edit_modal_html).to include("Guia do funil e etapas")
      expect(edit_modal_html).to include("target=\"_blank\"")
      expect(edit_modal_html).to include("data-ax-tooltip-option-texts-value")
      expect(edit_modal_html).to include("O lead precisa estar naquela etapa")
      expect(edit_modal_html).to include("kind: task_created")
      expect(edit_modal_html).to include("Sem ação do responsável")
      expect(edit_modal_html).to include("Nome do funil", "Tipo de negócio")
      expect(create_modal_html).to include("Nome da etapa", "Subtítulo", "Tipo da etapa")
      expect(create_modal_html).to include("Nome visível no funil", "Classificação interna usada")
      expect(create_modal_html).to include("Use Venda ou Locação")
      expect(document.at_css(".lead-pwa-filter-overlay")).to be_present
      lead_card_url = document.css("article.lead-kanban-card[data-lead-url]").find { |card| card.text.include?("Cliente Kanban") }["data-lead-url"]
      expect(lead_card_url).to start_with(admin_lead_path(Lead.find_by!(name: "Cliente Kanban")))
      expect(response.body).to include("Cliente Kanban")
      expect(response.body).to include("Em Atendimento")
      expect(response.body).not_to include("data-lead-kanban-drag-handle")
    end

    it "nao exibe o botao de relatorio sem permissao de relatorios de leads" do
      profile = Profile.create!(
        tenant: admin.tenant,
        name: "Perfil sem relatorio #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 9_100,
        permissions: { "leads" => { "view" => true, "scope" => "all" } }
      )
      user = create(:admin_user, tenant: admin.tenant, profile:, email: "sem-relatorio-#{SecureRandom.hex(6)}@salute.test")
      sign_in user

      get admin_leads_path

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(document.css('a[href*="/admin/leads/report"]').size).to eq(0)
      expect(document.css('input[name="include_captacoes"]').size).to eq(0)
    end

    it "exibe o botao de relatorio com permissao de relatorios de leads" do
      profile = Profile.create!(
        tenant: admin.tenant,
        name: "Perfil com relatorio #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 9_101,
        permissions: {
          "leads" => { "view" => true, "scope" => "all" },
          "lead_reports" => { "view" => true }
        }
      )
      user = create(:admin_user, tenant: admin.tenant, profile:, email: "com-relatorio-#{SecureRandom.hex(6)}@salute.test")
      sign_in user

      get admin_leads_path

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(document.at_css('a[href*="/admin/leads/report"]')).to be_present
      expect(document.at_css('input[name="include_captacoes"]')).to be_present
    end

    it "renderiza apenas o primeiro lote de 5 leads por coluna no kanban" do
      base_time = Time.zone.parse("2026-08-06 12:00:00")
      default_status = Lead.default_status(tenant: admin.tenant)
      6.times do |index|
        create(
          :lead,
          tenant: admin.tenant,
          name: "Lead Novo #{index}",
          phone: "1199999999#{index}",
          status: default_status,
          created_at: base_time - index.minutes
        )
      end

      get admin_leads_path(view: "kanban")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      column = document.at_css(%([data-lead-kanban-status="#{default_status}"]))
      expect(column.css(".lead-kanban-card").size).to eq(5)
      expect(column.to_html).to include("Lead Novo 0", "Lead Novo 4")
      expect(column.to_html).not_to include("Lead Novo 5")
      expect(column.at_css('.lead-kanban-loader[data-lead-kanban-offset="5"][data-lead-kanban-has-more="true"]')).to be_present
    end

    it "agrupa leads legados Novo na coluna inicial Novo Lead" do
      lead = create(:lead, tenant: admin.tenant, name: "Lead Legado Novo", phone: "11999999990")
      lead.update_columns(status: "Novo", lead_pipeline_stage_id: nil, updated_at: Time.current)

      get admin_leads_path(view: "kanban")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      initial_column = document.at_css(%([data-lead-kanban-status="#{Lead.default_status(tenant: admin.tenant)}"]))
      legacy_column = document.at_css(%([data-lead-kanban-status="Novo"]))

      expect(initial_column).to be_present
      expect(initial_column.text).to include("Lead Legado Novo")
      expect(legacy_column).to be_nil
    end

    it "carrega o proximo lote de uma coluna do kanban respeitando filtros" do
      base_time = Time.zone.parse("2026-08-06 12:00:00")
      default_status = Lead.default_status(tenant: admin.tenant)
      6.times do |index|
        create(
          :lead,
          tenant: admin.tenant,
          name: "Lead Incremental #{index}",
          phone: "1188888888#{index}",
          status: default_status,
          origin: "webhook",
          created_at: base_time - index.minutes
        )
      end
      create(:lead, tenant: admin.tenant, name: "Lead de Portal", status: default_status, origin: "portal")

      get kanban_column_admin_leads_path(
        view: "kanban",
        status: default_status,
        origin: "webhook",
        offset: 5,
        return_to: admin_leads_path(view: "kanban", origin: "webhook")
      )

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      expect(payload["loaded_count"]).to eq(1)
      expect(payload["has_more"]).to eq(false)
      expect(payload["next_offset"]).to eq(6)
      expect(payload["html"]).to include("Lead Incremental 5")
      expect(payload["html"]).not_to include("Lead de Portal")
    end

    it "mantem a visualizacao em lista como alternativa" do
      lead = create(:lead, name: "Cliente Lista", phone: "11999999999", status: "Novo")
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(
        status: "connected",
        waba_id: "waba-list",
        phone_number_id: "phone-list",
        access_token: "token-list",
        inbox_attendance_enabled: true
      )

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(response.body).to include("lead-list-workspace")
      expect(response.body).to include("lead-desktop-header")
      expect(response.body).not_to include("Total filtrado")
      expect(document.at_css("#leadDesktopFilterModal")).to be_present
      expect(document.at_css(".ax-workspace-heading")).to be_nil
      expect(response.body).to include("WhatsApp")
      expect(document.at_css("form[action='#{open_whatsapp_conversation_admin_lead_path(lead)}'][method='post']")).to be_present
      expect(document.at_css("a[href='#{admin_lead_path(lead, return_to: "#{admin_leads_path(view: "list")}#lead_#{lead.id}", anchor: "whatsapp")}']")).to be_nil
      expect(response.body).not_to include("<table")
      expect(response.body).to include("Cliente Lista")
    end

    it "oculta descartados da lista padrao e mostra quando filtrado ou no kanban" do
      active = create(:lead, tenant: admin.tenant, name: "Lead Ativo Lista", phone: "11999999999", status: "Novo")
      discarded = create(:lead, tenant: admin.tenant, name: "Lead Descartado Lista", phone: "11888888888", status: "Descartado")

      get admin_leads_path(view: "list", lead_tab: "all")

      expect(response).to have_http_status(:ok)
      list_text = Nokogiri::HTML(response.body).at_css(".lead-list").text
      expect(list_text).to include(active.name)
      expect(list_text).not_to include(discarded.name)

      get admin_leads_path(view: "list", lead_tab: "all", status: "Descartado")

      expect(response).to have_http_status(:ok)
      list_text = Nokogiri::HTML(response.body).at_css(".lead-list").text
      expect(list_text).to include(discarded.name)

      get admin_leads_path(view: "kanban", lead_tab: "all")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      discarded_column = document.at_css(%([data-lead-kanban-status="#{Lead.status_value('Descartado')}"]))
      expect(discarded_column.text).to include(discarded.name)
    end

    it "lista as filas de distribuição ativas nas automações do modal de etapas" do
      rule = create(:distribution_rule, tenant: admin.tenant, name: "Fila Premium", distribution_mode: :rotary)
      agent = create(:admin_user, tenant: admin.tenant, role: :editor)
      create(:distribution_rule_agent, tenant: admin.tenant, distribution_rule: rule, admin_user: agent)

      get admin_leads_path(view: "kanban")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Manter fila atual do lead")
      expect(response.body).to include("Fila Premium")
      expect(response.body).to include("Rodízio")
      expect(response.body).to include("1 corretor")
    end

    it "renderiza a experiencia PWA com abas e favoritos nativos do corretor logado" do
      favorite = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Favorito PWA", phone: "11999999999", status: "Em Atendimento")
      create(:lead_favorite, tenant: admin.tenant, admin_user: admin, lead: favorite)
      other = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Normal PWA", phone: "11888888888", status: "Novo")

      get admin_leads_path(view: "list", mobile_tab: "favorites")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".lead-pwa-screen")).to be_present
      expect(document.css(".lead-pwa-tab").map(&:text).join).to include("A fazer", "Visitas", "Futuras", "Favoritos", "Todos")
      expect(document.at_css(".lead-pwa-tab.is-active").text).to include("Favoritos")
      expect(document.css(".lead-pwa-card").map(&:text).join).to include("Lead Favorito PWA")
      expect(document.css(".lead-pwa-card").map(&:text).join).not_to include("Lead Normal PWA")
      expect(response.body).to include("bi-star-fill")
      expect(other).to be_persisted
    end

    it "renderiza cards do Kanban PWA com gestos e acoes rapidas" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Arrastavel PWA", phone: "11999999999", status: "Novo")

      get admin_leads_path(view: "kanban")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      column = document.at_css(%(.lead-pwa-kanban-column[data-lead-status="#{Lead.default_status(tenant: admin.tenant)}"]))
      card = document.at_css("article#lead_#{lead.id}.lead-pwa-card[data-lead-pwa-kanban-target='card']")

      expect(column).to be_present
      expect(card).to be_present
      expect(card["data-action"]).to include("prepareCardGesture", "moveCardGesture", "openQuickSheet")
      expect(card["data-update-url"]).to eq(admin_lead_path(lead))
      expect(card["data-whatsapp-url"]).to eq(open_whatsapp_conversation_admin_lead_path(lead, workspace: "focus"))
      expect(document.at_css(".lead-pwa-kanban-sheet[data-lead-pwa-kanban-target='sheet']")).to be_present
    end

    it "reconcilia as abas PWA com agendamentos ja importados" do
      travel_to Time.zone.local(2026, 8, 15, 10, 0, 0) do
        future = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Retorno Futuro Importado", phone: "11999999991", status: "Em Atendimento")
        due = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Retorno Hoje Importado", phone: "11999999992", status: "Em Atendimento")
        visit = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Visita Importada", phone: "11999999993", status: "Em Atendimento")

        create(
          :lead,
          tenant: admin.tenant,
          admin_user: admin,
          name: "Lead Novo Sem Agenda",
          phone: "11999999994",
          status: "Novo"
        )

        create(
          :task,
          tenant: admin.tenant,
          lead: future,
          admin_user: admin,
          title: "Ação agendada do legado",
          due_at: Time.zone.local(2026, 8, 15, 9, 0, 0),
          status: "pendente",
          kind: "follow_up"
        ).tap do |task|
          LeadActivity.log!(
            lead: future,
            kind: "external_scheduled_action",
            metadata: {
              source: ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
              external_key: "future-1",
              task_id: task.id,
              title: "Ação agendada do legado",
              due_at: task.due_at.iso8601,
              raw: {
                id: "future-1",
                status: "Em aberto",
                schedulated_action_date: "2026-08-20T09:00:00.000-03:00",
                schedulated_action_name: "Retornar para o cliente",
                schedulated_action_type_alias: "feedback_customer"
              }
            }
          )
        end

        LeadActivity.log!(
          lead: due,
          kind: "external_scheduled_action",
          metadata: {
            source: ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
            external_key: "due-1",
            raw: {
              id: "due-1",
              status: "Em aberto",
              schedulated_action_date: "2026-08-15T14:00:00.000-03:00",
              schedulated_action_name: "Retornar para o cliente",
              schedulated_action_type_alias: "feedback_customer"
            }
          }
        )

        LeadActivity.log!(
          lead: visit,
          kind: "external_scheduled_action",
          metadata: {
            source: ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
            external_key: "visit-1",
            raw: {
              id: "visit-1",
              status: "Em aberto",
              schedulated_action_date: "2026-08-17T15:30:00.000-03:00",
              schedulated_action_name: "Visita Agendada",
              schedulated_action_type_alias: "scheduled_visit"
            }
          }
        )

        get admin_leads_path(view: "list", mobile_tab: "future")

        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        expect(document.at_css(".lead-pwa-tab.is-active").text).to include("Futuras", "3")
        expect(document.css(".lead-pwa-card").map(&:text).join).to include(
          "Retorno Futuro Importado",
          "Retornar para o cliente - 20/08/2026 09:00",
          "Retorno Hoje Importado",
          "Visita Importada"
        )

        get admin_leads_path(view: "list", mobile_tab: "visits")

        document = Nokogiri::HTML(response.body)
        expect(document.at_css(".lead-pwa-tab.is-active").text).to include("Visitas", "1")
        expect(document.css(".lead-pwa-card").map(&:text).join).to include("Visita Importada", "Visita marcada - 17/08/2026 15:30")

        get admin_leads_path(view: "list", mobile_tab: "todo")

        document = Nokogiri::HTML(response.body)
        card_text = document.css(".lead-pwa-card").map(&:text).join
        expect(document.at_css(".lead-pwa-tab.is-active").text).to include("A fazer", "1")
        expect(card_text).to include("Lead Novo Sem Agenda")
        expect(card_text).not_to include("Retorno Futuro Importado", "Retorno Hoje Importado", "Visita Importada")
        expect(card_text).not_to include("C2S")
      end
    end

    it "mostra todos os leads na listagem geral sem filtrar por funil" do
      sale_pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Venda")
      sale_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: sale_pipeline, name: "Proposta venda")
      rental_pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Locação")
      rental_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: rental_pipeline, name: "Proposta locação")
      create(:lead, tenant: admin.tenant, name: "Lead Venda Geral", phone: "11999999999", lead_pipeline: sale_pipeline, lead_pipeline_stage: sale_stage, status: sale_stage.name)
      create(:lead, tenant: admin.tenant, name: "Lead Locação Geral", phone: "11888888888", lead_pipeline: rental_pipeline, lead_pipeline_stage: rental_stage, status: rental_stage.name)

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Venda Geral", "Lead Locação Geral")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("select#lead_pipeline_id option[value='']").text).to include("Todos os funis")
    end

    it "lista leads por rota dedicada do funil sem perder o filtro do funil" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Venda")
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Proposta")
      matching = create(:lead, tenant: admin.tenant, name: "Lead do Funil Venda", phone: "11999999999", lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)
      create(:lead, tenant: admin.tenant, name: "Lead de Outro Funil", phone: "11888888888", status: "Novo")

      get admin_lead_pipeline_leads_path(pipeline, view: "list")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(matching.name)
      expect(response.body).not_to include("Lead de Outro Funil")
      document = Nokogiri::HTML(response.body)
      today_link = document.at_css(".lead-filter-quick__chip[href*='start_date']")
      expect(today_link["href"]).to include("lead_pipeline_id=#{pipeline.id}")
      expect(document.at_css("a.ax-nav__link.active[href='#{admin_lead_pipeline_leads_path(pipeline, view: "kanban")}']")).to be_present
    end

    it "lembra a visualizacao escolhida pelo usuario entre sessoes" do
      create(:lead, name: "Cliente Memoria", phone: "11999999999", status: "Novo")

      get admin_leads_path(view: "list")
      expect(admin.reload.leads_view_mode).to eq("list")

      # Sem param e em nova sessao, volta na preferencia salva (nao no padrao).
      sign_out admin
      sign_in admin
      get admin_leads_path

      expect(response.body).to include("lead-list-workspace")
    end

    it "filtra por corretor, imóvel, contato e período" do
      broker = create(:admin_user, email: "broker-filter-#{SecureRandom.hex(8)}@salute.test")
      other_broker = create(:admin_user, email: "broker-filter-other-#{SecureRandom.hex(8)}@salute.test")
      property = create(:habitation, codigo: "lead-filter-#{SecureRandom.hex(6)}", titulo_anuncio: "Apartamento Filtro Lead")

      matching = create(:lead, name: "Lead Filtrado", phone: "11999999999", created_at: 1.day.ago, property_id: property.id)
      matching.update_columns(admin_user_id: broker.id, created_at: 1.day.ago, updated_at: 1.day.ago)

      other = create(:lead, name: "Lead Fora do Filtro", phone: "11888888888", email: "fora@example.com", created_at: 20.days.ago)
      other.update_columns(admin_user_id: other_broker.id, created_at: 20.days.ago, updated_at: 20.days.ago)

      get admin_leads_path(
        view: "list",
        broker_id: broker.id,
        property_q: property.codigo,
        property_filter: "with_property",
        contact_filter: "with_phone",
        start_date: 3.days.ago.to_date.iso8601,
        end_date: Date.current.iso8601
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Filtrado")
      expect(response.body).to include("Apartamento Filtro Lead")
      expect(response.body).to include("Corretor")
      expect(response.body).to include("Imóvel")
      expect(response.body).to include("Contato")
      expect(response.body).to include("Entrada: #{I18n.l(3.days.ago.to_date)} a #{I18n.l(Date.current)}")
      document = Nokogiri::HTML(response.body)
      filter_modal = document.at_css("#leadDesktopFilterModal")
      expect(filter_modal.text).to include("Período do lead", "Entrada de", "Entrada até", "Fechado de", "Fechado até")
      expect(filter_modal.css(".lead-filter-date-pair").size).to eq(2)
      expect(filter_modal.at_css('input[name="start_date"]')["value"]).to eq(3.days.ago.to_date.iso8601)
      expect(filter_modal.at_css('input[name="end_date"]')["value"]).to eq(Date.current.iso8601)
      expect(response.body).not_to include("Lead Fora do Filtro")
    end

    it "nao inclui leads anteriores ao campo entrada de" do
      broker = create(:admin_user, tenant: admin.tenant, email: "broker-range-#{SecureRandom.hex(8)}@salute.test")
      inside = create(:lead, tenant: admin.tenant, name: "Lead Dentro do Periodo", phone: "11999999999")
      inside.update_columns(admin_user_id: broker.id, created_at: Time.zone.parse("2026-08-24 09:00"), updated_at: Time.zone.parse("2026-08-24 09:00"))
      outside = create(:lead, tenant: admin.tenant, name: "Lead Dia Vinte", phone: "11888888888")
      outside.update_columns(admin_user_id: broker.id, created_at: Time.zone.parse("2026-08-20 10:00"), updated_at: Time.zone.parse("2026-08-20 10:00"))

      get admin_leads_path(
        view: "list",
        lead_tab: "all",
        broker_id: broker.id,
        start_date: "2026-08-24",
        end_date: "2026-08-31"
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(inside.name)
      expect(response.body).not_to include(outside.name)
      expect(response.body).to include("Entrada: 24/08/2026 a 31/08/2026")

      document = Nokogiri::HTML(response.body)
      filter_modal = document.at_css("#leadDesktopFilterModal")
      expect(filter_modal.at_css('input[name="start_date"]')["value"]).to eq("2026-08-24")
      expect(filter_modal.at_css('input[name="end_date"]')["value"]).to eq("2026-08-31")
    end

    it "filtra leads por tentativa sem sucesso e elegibilidade de redistribuicao" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Atendimento comercial")
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Primeiro atendimento")
      next_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Segunda tentativa")
      create(
        :lead_pipeline_stage_automation,
        tenant: admin.tenant,
        lead_pipeline_stage: stage,
        auto_advance_to_stage: next_stage,
        action_type: "redistribute_lead",
        action_config: { "unsuccessful_attempt_limit" => 1 }
      )
      matching = create(:lead, tenant: admin.tenant, admin_user: admin, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name, name: "Lead Sem Resposta")
      other = create(:lead, tenant: admin.tenant, admin_user: admin, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name, name: "Lead Respondido")
      LeadActivity.create!(tenant: admin.tenant, lead: matching, kind: "note", metadata: { contact_kind: "whatsapp", contact_result: "nao_respondeu" })
      LeadActivity.create!(tenant: admin.tenant, lead: other, kind: "note", metadata: { contact_kind: "nota", body: "Anotação interna" })

      get admin_leads_path(view: "list", attention_filter: "unsuccessful_attempts")

      expect(response).to have_http_status(:ok)
      list_text = Nokogiri::HTML(response.body).at_css(".lead-list").text
      expect(list_text).to include("Lead Sem Resposta")
      expect(list_text).not_to include("Lead Respondido")

      get admin_leads_path(view: "list", attention_filter: "eligible_redistribution")

      expect(response).to have_http_status(:ok)
      list_text = Nokogiri::HTML(response.body).at_css(".lead-list").text
      expect(list_text).to include("Lead Sem Resposta")
      expect(list_text).not_to include("Lead Respondido")
    end

    it "filtra por tags em lista e kanban" do
      create(:lead, name: "Lead Premium", phone: "11999999999", status: "Novo", tags: ["Produto", "Premium"])
      create(:lead, name: "Lead Popular", phone: "11888888888", status: "Novo", tags: ["Popular"])

      get admin_leads_path(view: "list", tags: ["Premium"])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Premium")
      expect(response.body).to include("Tags")
      expect(response.body).not_to include("Lead Popular")

      get admin_leads_path(view: "kanban", tags: ["Premium"])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Premium")
      expect(response.body).not_to include("Lead Popular")
    end

    it "renderiza o filtro mobile com campos reais do backend" do
      create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead com filtro PWA", phone: "11999999999", status: "Novo", tags: ["Quente"])

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      panel = document.at_css(".lead-pwa-filter-panel")
      overlay = document.at_css(".lead-pwa-filter-overlay")
      expect(panel).to be_present
      expect(overlay).to be_present
      expect(overlay.attribute("hidden")).to be_present
      expect(document.at_css('.ax-leads-mobile-shell[data-controller="lead-pwa-filter"]')).to be_present
      expect(document.at_css('.lead-pwa-filter[data-action="lead-pwa-filter#open"]')).to be_present
      expect(panel.at_css('.lead-pwa-filter-panel__close[data-action="lead-pwa-filter#close"]')).to be_present
      expect(response.body).not_to include("data-controller=\"ax-aside\"")
      expect(response.body).not_to include("data-ax-aside-target")
      expect(panel.text).to include("Minha visualização dos leads", "Natureza de negociação", "Status do lead", "Atividade atual do lead", "Faixa de preço")
      expect(panel.at_css("input[name='business_filter[]'][value='sale']")).to be_present
      expect(panel.at_css("input[name='activity_filter[]'][value='scheduled_visit']")).to be_present
      expect(panel.at_css("input[name='channel_filter[]'][value='whatsapp']")).to be_present
      expect(panel.at_css("input[name='price_min']")).to be_present
      expect(panel.at_css("input[name='closed_start_date']")).to be_present
      expect(document.at_css(".lead-pwa-clear-filter")).to be_nil
    end

    it "mantem contadores originais nas abas PWA e mostra filtro aplicado apenas na aba ativa" do
      travel_to Time.zone.local(2026, 8, 15, 10, 0, 0) do
        raquel = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Raquel Futura", phone: "11999999991", status: "Em Atendimento")
        outro = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Outro Futuro", phone: "11999999992", status: "Em Atendimento")
        create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead sem busca", phone: "11999999993", status: Lead.default_status(tenant: admin.tenant))

        [raquel, outro].each_with_index do |lead, index|
          create(
            :task,
            tenant: admin.tenant,
            lead: lead,
            admin_user: admin,
            title: "Retornar futuro #{index}",
            due_at: Time.zone.local(2026, 8, 20 + index, 9, 0, 0),
            status: "pendente",
            kind: "follow_up"
          )
        end

        get admin_leads_path(view: "list", mobile_tab: "future", q: "raquel")

        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        tabs_by_label = document.css(".lead-pwa-tab").index_by { |tab| tab.at_css(".lead-pwa-tab__label")&.text&.strip }

        expect(tabs_by_label.fetch("Futuras").text).to include("1/2")
        expect(tabs_by_label.fetch("A fazer").text).to include("1")
        expect(tabs_by_label.fetch("Todos").text).to include("3")
        expect(document.at_css(".lead-pwa-clear-filter")).to be_present
        expect(document.at_css(".lead-pwa-clear-filter")["href"]).to eq(admin_leads_path(view: "list", mobile_tab: "future"))

        get admin_leads_path(view: "list", mobile_tab: "future", q: "Rraquel")

        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        tabs_by_label = document.css(".lead-pwa-tab").index_by { |tab| tab.at_css(".lead-pwa-tab__label")&.text&.strip }
        expect(tabs_by_label.fetch("Futuras").text).to include("1/2")
        expect(response.body).to include("Raquel Futura")
      end
    end

    it "exibe a posicao da fila no header e remove a fila do rodape PWA" do
      broker_profile = Profile.create!(
        tenant: admin.tenant,
        name: "Corretor fila #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 8_900,
        permissions: { "leads" => { "view" => true, "scope" => "all" } }
      )
      broker = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Gabriela Machado")
      internal_rule = create(
        :distribution_rule,
        tenant: admin.tenant,
        name: ExternalLeadIntegration::SUPPORT_RULE_NAME,
        active: true,
        source_webhook: true,
        webhook_tags: [ExternalLeadIntegration::WEBHOOK_TAG]
      )
      operational_rule = create(:distribution_rule, tenant: admin.tenant, name: "Equipe vendas", active: true)
      create(:distribution_rule_agent, distribution_rule: internal_rule, admin_user: broker, position: 1)
      create(:distribution_rule_agent, distribution_rule: operational_rule, admin_user: broker, position: 6)
      sign_out admin
      sign_in broker

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      bottom_nav = document.at_css(".ax-pwa-bottom-nav")
      expect(bottom_nav).to be_present
      expect(bottom_nav.css(".ax-pwa-bottom-nav__item[data-admin-navigation-ignore]")).to be_empty
      expect(document.at_css(".lead-pwa-queue")["href"]).to eq(distribution_queue_admin_leads_path)
      expect(document.at_css(".lead-desktop-queue")["href"]).to eq(distribution_queue_admin_leads_path)
      expect(document.at_css(".lead-pwa-queue").text).to include("1º", "na fila")
      expect(bottom_nav.text).not_to include("Fila")
    end

    it "mostra no header a posicao real do usuario dentro da fila operacional" do
      broker_profile = Profile.create!(
        tenant: admin.tenant,
        name: "Corretor fila #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 8_905,
        permissions: { "leads" => { "view" => true, "scope" => "all" } }
      )
      first_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Tayana Agne")
      second_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Fábio Luís Avallone")
      current_user = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Renata Santos Cardoso")
      rule = create(:distribution_rule, tenant: admin.tenant, name: "Equipe vendas", active: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_agent, position: 97)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: second_agent, position: 98)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: current_user, position: 99)
      sign_out admin
      sign_in current_user

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".lead-desktop-queue").text).to include("3º", "na fila")
      expect(document.at_css(".lead-pwa-queue").text).to include("3º", "na fila")
    end

    it "lista apenas filas de distribuicao em que o usuario logado participa" do
      broker_profile = Profile.create!(
        tenant: admin.tenant,
        name: "Corretor fila #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 8_901,
        permissions: { "leads" => { "view" => true, "scope" => "all" } }
      )
      current_user = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Gabriela Machado")
      teammate = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Maria Elisabete")
      second_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Leticia Rossatto")
      third_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Levi Ribeiro")
      fourth_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Tayana Agne")
      fifth_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Fábio Luís Avallone")
      seventh_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Renata Santos Cardoso")
      eighth_agent = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Karla Luiza Barcelos Guimarães")
      outside_user = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Corretor fora da fila")
      internal_user = create(:admin_user, tenant: admin.tenant, profile: broker_profile, name: "Sistema Interno")
      included_rule = create(:distribution_rule, tenant: admin.tenant, name: "Equipe vendas", active: true, distribution_mode: :rotary)
      other_rule = create(:distribution_rule, tenant: admin.tenant, name: "Fila sem o logado", active: true, distribution_mode: :rotary)
      internal_rule = create(
        :distribution_rule,
        tenant: admin.tenant,
        name: ExternalLeadIntegration::SUPPORT_RULE_NAME,
        active: true,
        distribution_mode: :rotary,
        source_webhook: true,
        webhook_tags: [ExternalLeadIntegration::WEBHOOK_TAG]
      )

      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: teammate, position: 97)
      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: second_agent, position: 98)
      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: third_agent, position: 99)
      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: fourth_agent, position: 100)
      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: fifth_agent, position: 101)
      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: current_user, position: 102)
      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: seventh_agent, position: 103)
      create(:distribution_rule_agent, distribution_rule: included_rule, admin_user: eighth_agent, position: 104)
      create(:distribution_rule_agent, distribution_rule: other_rule, admin_user: outside_user, position: 1)
      create(:distribution_rule_agent, distribution_rule: internal_rule, admin_user: current_user, position: 1)
      create(:distribution_rule_agent, distribution_rule: internal_rule, admin_user: internal_user, position: 2)
      sign_out admin
      sign_in current_user

      get distribution_queue_admin_leads_path

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      card = document.at_css(".lead-queue-card")
      agents = card.css(".lead-queue-agent")
      current_agent = document.at_css(".lead-queue-agent.is-current")

      expect(document.at_css(".lead-queue-command").text).to include("Minhas filas")
      expect(document.at_css(".lead-queue-mobile-top").text).to include("Minhas filas", "1 fila operacional", "6º")
      expect(card.text).to include("Equipe vendas", "6º de 8", "Maria Elisabete")
      expect(agents.size).to eq(8)
      expect(agents.map { |agent| agent.at_css(".lead-queue-agent__position").text.strip }).to eq(%w[1º 2º 3º 4º 5º 6º 7º 8º])
      expect(agents.first.text).to include("Maria Elisabete", "1º")
      expect(current_agent.text).to include(current_user.name, "Você", "6º")
      expect(document.text).not_to include("Fila sem o logado", "Corretor fora da fila", ExternalLeadIntegration::SUPPORT_RULE_NAME, "Sistema Interno")
    end

    it "aplica filtros mobile de natureza, canal e faixa de preço no banco" do
      property = create(:habitation, tenant: admin.tenant, titulo_anuncio: "Cobertura Venda", valor_venda_cents: 850_000_00, valor_locacao_cents: 0)
      matching = create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        name: "Lead Compra WhatsApp",
        phone: "11999999999",
        status: "Novo",
        origin: "WhatsApp",
        lead_type: "whatsapp",
        product: "Compra cobertura",
        property_id: property.id
      )
      create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        name: "Lead Locacao Site",
        phone: "11888888888",
        status: "Novo",
        origin: "Site",
        product: "Aluguel apartamento",
        attribution_data: { "product" => { "price_float" => "3500.0" } }
      )

      get admin_leads_path(
        view: "list",
        business_filter: ["sale"],
        channel_filter: ["whatsapp"],
        price_min: "800000",
        price_max: "900000"
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(matching.name)
      expect(response.body).to include("Natureza", "Canal de origem", "Preço")
      expect(response.body).not_to include("Lead Locacao Site")
    end

    it "filtra negócio fechado pela data real de fechamento e não pela última edição" do
      closed_status = admin.tenant.lead_pipeline_stages.active.where(stage_type: "won").ordered.first&.name || Lead.status_value(:concluido)
      closed_in_period = create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        name: "Fechado no período",
        phone: "11999999990",
        status: closed_status,
        closed_at: Time.zone.local(2026, 8, 15, 10, 0, 0),
        updated_at: Time.zone.local(2026, 8, 17, 10, 0, 0)
      )
      edited_after_close = create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        name: "Fechado antes editado depois",
        phone: "11999999991",
        status: closed_status,
        closed_at: Time.zone.local(2026, 8, 10, 10, 0, 0),
        updated_at: Time.zone.local(2026, 8, 15, 10, 0, 0)
      )

      get admin_leads_path(
        view: "list",
        closed_start_date: "2026-08-15",
        closed_end_date: "2026-08-15"
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(closed_in_period.name)
      expect(response.body).to include("Período")
      expect(response.body).not_to include(edited_after_close.name)
    end

    it "aplica filtros mobile de atividade usando tarefas e visitas reais" do
      visit_lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Visita Real", phone: "11999999991", status: "Em Atendimento")
      task_lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Retorno Real", phone: "11999999992", status: "Em Atendimento")
      create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Sem Agenda", phone: "11999999993", status: "Em Atendimento")
      Appointment.create!(
        tenant: admin.tenant,
        lead: visit_lead,
        admin_user: admin,
        title: "Visita no imóvel",
        kind: "visita",
        status: "agendado",
        starts_at: 2.days.from_now
      )
      create(:task, tenant: admin.tenant, lead: task_lead, admin_user: admin, title: "Retornar para o cliente", due_at: 1.day.from_now)

      get admin_leads_path(view: "list", activity_filter: ["scheduled_visit"])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Visita Real")
      expect(response.body).not_to include("Lead Retorno Real", "Lead Sem Agenda")

      get admin_leads_path(view: "list", activity_filter: ["return_customer"])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Retorno Real")
      expect(response.body).not_to include("Lead Visita Real", "Lead Sem Agenda")
    end

    it "nao filtra por corretor de outro tenant mesmo se houver lead legado inconsistente" do
      other_tenant = Tenant.create!(name: "Outro leads filter #{SecureRandom.hex(3)}", slug: "outro-leads-filter-#{SecureRandom.hex(3)}")
      other_profile = other_tenant.profiles.find_by!(key: "agent")
      other_broker = create(:admin_user, tenant: other_tenant, profile: other_profile, email: "other-broker-filter-#{SecureRandom.hex(6)}@salute.test")
      legacy_lead = create(:lead, name: "Lead Inconsistente", phone: "11977777777", tenant: admin.tenant)
      legacy_lead.update_columns(admin_user_id: other_broker.id)

      get admin_leads_path(view: "list", broker_id: other_broker.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Lead Inconsistente")
    end

    it "recorta a listagem com team=0 sem bloquear acesso direto a lead subordinado" do
      manager_profile = Profile.create!(
        tenant: admin.tenant,
        name: "Manager Leads #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 200,
        permissions: { "leads" => { "view" => true, "manage" => true, "scope" => "team" } }
      )
      agent_profile = admin.tenant.profiles.find_or_create_by!(key: "agent") do |profile|
        profile.name = "Agent"
        profile.axis = "vertical"
        profile.permissions = Profile.default_permissions_for("Corretor")
      end
      manager = create(:admin_user, tenant: admin.tenant, profile: manager_profile, email: "manager-leads-#{SecureRandom.hex(6)}@salute.test")
      subordinate = create(:admin_user, tenant: admin.tenant, profile: agent_profile, manager: manager, email: "subordinate-leads-#{SecureRandom.hex(6)}@salute.test")
      own_lead = create(:lead, name: "Lead do Gestor", phone: "11911111111", tenant: admin.tenant, admin_user: manager)
      team_lead = create(:lead, name: "Lead Subordinado", phone: "11922222222", tenant: admin.tenant, admin_user: subordinate)

      sign_out admin
      sign_in manager

      get admin_leads_path(view: "list", team: "0")

      expect(response).to have_http_status(:ok)
      team_toggle = Nokogiri::HTML(response.body).at_css('a.ax-team-toggle[role="switch"]')
      expect(team_toggle).to be_present
      expect(team_toggle["aria-checked"]).to eq("false")
      expect(URI.parse(team_toggle["href"]).query).to include("team=1", "view=list")
      expect(response.body).to include(own_lead.name)
      expect(response.body).not_to include(team_lead.name)

      get admin_lead_path(team_lead, team: "0")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(team_lead.name)
    end
  end

  describe "GET /admin/leads/:id" do
    it "renderiza o detalhe PWA preservando a tela completa do desktop" do
      property = create(:habitation, tenant: admin.tenant, codigo: "PWA-001")
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Detalhe PWA", phone: "11999999999", status: "Em Atendimento", notes: "Preferência por vista mar.")
      Task.create!(tenant: admin.tenant, lead: lead, admin_user: admin, title: "Retornar para o cliente", due_at: 1.hour.ago, status: "pendente")
      LeadActivity.log!(lead: lead, kind: "note", metadata: { body: "Cliente pediu retorno no fim da tarde.", by: "Corretor" })
      lead.property_interests.create!(tenant: admin.tenant, habitation: property)
      lead.ai_property_share_collections.create!(admin_user: admin).tap do |collection|
        collection.items.create!(habitation: property)
      end

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      pwa_detail = document.at_css(".lead-pwa-detail")
      expect(pwa_detail).to be_present
      expect(pwa_detail.text).to include("Lead Detalhe PWA", "Ações do lead", "Retornar para o cliente", "Imóveis de interesse", "PWA-001", "Links gerados")
      expect(pwa_detail.text).to include("Histórico de contatos", "Registrar contato", "Anotação interna", "Cliente pediu retorno no fim da tarde.", "Etiquetas", "Contato")
      expect(pwa_detail.text).not_to include("Inteligência de Interesse")
      expect(pwa_detail.text).not_to include("Adicionar anotação")
      expect(pwa_detail.text).not_to include("Conversa")
      expect(pwa_detail.at_css(".lead-pwa-chat-dialog")).to be_nil
      expect(pwa_detail.at_css(".lead-whatsapp-card")).to be_nil
      expect(document.at_css(".lead-show-workspace .lead-whatsapp-card")).to be_present
      expect(pwa_detail.at_css("#lead-pwa-tarefas .lead-detail-task-row")).to be_present
      expect(pwa_detail.at_css("form[action='#{log_contact_admin_lead_path(lead)}']")).to be_present
      expect(pwa_detail.text.index("Histórico de contatos")).to be < pwa_detail.text.index("Propostas")
      expect(document.at_css("form[action='#{toggle_favorite_admin_lead_path(lead)}']")).to be_present
      desktop_heading = document.at_css(".lead-show-workspace .ax-workspace-heading")
      expect(desktop_heading).to be_present
      expect(desktop_heading.text).to include("Transferir", "Favoritar", "Histórico")
      expect(desktop_heading.at_css("button[data-action='ax-modal#open']")).to be_present
      expect(desktop_heading.at_css("form[action='#{toggle_favorite_admin_lead_path(lead)}']")).to be_present
      expect(document.at_css("form[action='#{admin_lead_path(lead)}'][method='post'] input[name='_method'][value='delete']")).to be_present
      expect(document.at_css("#leadTimelineSection:not([hidden])")).to be_present
    end

    it "organiza agenda tarefas etiquetas e propostas em secoes operacionais do lead" do
      property = create(:habitation, tenant: admin.tenant, codigo: "PROP-001")
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Operacional", phone: "11999990000", status: "Em Atendimento", property_id: property.id)
      create(:appointment, tenant: admin.tenant, lead:, admin_user: admin, title: "Visita marcada", starts_at: 1.day.from_now, location: "Imóvel")
      create(:task, tenant: admin.tenant, lead:, admin_user: admin, title: "Ligar para cliente", due_at: 2.hours.from_now)
      label = create(:lead_label, tenant: admin.tenant, admin_user: admin, name: "Urgente")
      lead.lead_labelings.create!(tenant: admin.tenant, lead_label: label)
      Proposal.create!(lead:, admin_user: admin, status: "rascunho", title: "Proposta inicial", validade: 5.days.from_now.to_date, valor_cents: 850_000_00)

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      operation_card = document.at_css(".lead-show-workspace .lead-next-action-card")
      action_hub = operation_card&.at_css(".lead-action-hub")

      expect(operation_card).to be_present
      expect(action_hub).to be_present
      expect(operation_card.text).to include("Ações do lead", "Tarefa", "Agendar", "Proposta")
      expect(action_hub.text).not_to include("Contato")
      expect(operation_card.css(".lead-operational-section__title").map(&:text).join(" ")).to include("Agenda", "Tarefas", "Etiquetas", "Histórico de contatos", "Propostas")
      expect(operation_card.to_html).to include("Visita marcada", "Ligar para cliente", "Urgente", "R$ 850.000,00")
      expect(operation_card.text.index("Histórico de contatos")).to be < operation_card.text.index("Propostas")
      agenda_section = operation_card.css(".lead-operational-section").find { |section| section.text.include?("Agenda") }
      tasks_section = operation_card.css(".lead-operational-section").find { |section| section.text.include?("Tarefas") }
      labels_section = operation_card.css(".lead-operational-section").find { |section| section.text.include?("Etiquetas") }
      proposals_section = operation_card.css(".lead-operational-section").find { |section| section.text.include?("Propostas") }
      expect(agenda_section.to_html).to include("bi-plus-lg")
      expect(tasks_section.to_html).to include("bi-plus-lg")
      expect(labels_section.to_html).to include("bi-plus-lg")
      expect(proposals_section.to_html).to include("bi-plus-lg")
      reactive_form_actions = [
        admin_tasks_path,
        schedule_activity_admin_lead_path(lead),
        admin_lead_proposals_path(lead)
      ]
      reactive_form_actions.each do |action|
        expect(operation_card.css("form[action='#{action}'][data-turbo='false']")).to be_empty
      end
      expect(operation_card.at_css('a[href="#lead-desktop-agenda"]')).to be_present
      expect(operation_card.at_css('a[href="#lead-desktop-tarefas"]')).to be_present
      expect(operation_card.at_css('a[href="#lead-desktop-etiquetas"]')).to be_present
      expect(operation_card.at_css('a[href="#lead-desktop-propostas"]')).to be_present
      expect(operation_card.css('button[aria-label="Nova proposta"]').size).to be >= 1
      expect(operation_card.css("#newProposalLeadSidebar")).to be_empty
      expect(operation_card.to_html).not_to include("newProposalLeadAction")
      expect(operation_card.to_html).not_to include("Criar a primeira")
    end

    it "renderiza o detalhe quando ha imovel recente sem titulo e sem dormitorios" do
      create(:habitation, tenant: admin.tenant, titulo_anuncio: nil, dormitorios_qtd: nil, categoria: "Apartamento", bairro: "Centro", codigo: "SEM-TITULO")
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead com seletor de proposta", status: "Em Atendimento")

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead com seletor de proposta")
      expect(response.body).to include("SEM-TITULO")
    end

    it "resume entregas de notificacao push e aceite do corretor na linha do tempo do usuario comum" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Notificado", phone: "11999990001", status: "Em Atendimento")
      subscription = PushSubscription.create!(
        admin_user: admin,
        endpoint: "https://web.push.apple.com/Q/#{SecureRandom.hex(12)}",
        p256dh: "p256dh-test",
        auth: "auth-test",
        platform: "web",
        user_agent: "Mobile Safari"
      )

      PushDeliveryEvent.record!(
        event_type: "provider_accepted",
        admin_user_id: admin.id,
        push_subscription: subscription,
        lead_id: lead.id,
        tag: "lead-#{lead.id}-#{admin.id}",
        endpoint: subscription.endpoint,
        provider_status: "201",
        metadata: { channel: "push", notification_context: "distribution", admin_user_name: admin.name }
      )
      PushDeliveryEvent.record!(
        event_type: "device_received",
        admin_user_id: admin.id,
        push_subscription: subscription,
        lead_id: lead.id,
        tag: "lead-#{lead.id}-#{admin.id}",
        endpoint: subscription.endpoint,
        metadata: { channel: "push" }
      )
      LeadActivity.log!(
        lead: lead,
        kind: "notification_sent",
        metadata: { channel: "push", admin_user_name: admin.name }
      )
      LeadActivity.log!(
        lead: lead,
        kind: "accepted",
        metadata: { by: admin.name, via: "push", secure_link: true }
      )

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      timeline = document.at_css("#leadTimelineSection")

      expect(timeline.text).to include("Aviso enviado ao corretor")
      expect(timeline.text).to include("Notificação recebida no aparelho")
      expect(timeline.text).to include("pelo app instalado pelo Safari")
      expect(timeline.text).to include("Lead atendido")
      expect(timeline.text).to include("canal notificação do aplicativo")
      expect(timeline.text).not_to include("Envio da notificação confirmado")
      expect(timeline.text).not_to include("confirmação 201")
    end

    it "mostra detalhes de envio quando o admin esta acessando como o corretor" do
      impersonator = build_stubbed(:admin_user, name: "Admin do Sistema")
      allow_any_instance_of(Admin::LeadsController).to receive(:impersonating_admin_user?).and_return(true)
      allow_any_instance_of(Admin::LeadsController).to receive(:impersonation_admin_user).and_return(impersonator)
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Auditoria", phone: "11999990002", status: "Em Atendimento")
      subscription = PushSubscription.create!(
        admin_user: admin,
        endpoint: "https://web.push.apple.com/Q/#{SecureRandom.hex(12)}",
        p256dh: "p256dh-test",
        auth: "auth-test",
        platform: "web",
        user_agent: "Mobile Safari"
      )

      PushDeliveryEvent.record!(
        event_type: "provider_accepted",
        admin_user_id: admin.id,
        push_subscription: subscription,
        lead_id: lead.id,
        tag: "lead-#{lead.id}-#{admin.id}",
        endpoint: subscription.endpoint,
        provider_status: "201",
        metadata: { channel: "push", notification_context: "distribution", admin_user_name: admin.name }
      )

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      timeline = Nokogiri::HTML(response.body).at_css("#leadTimelineSection")

      expect(timeline.text).to include("Envio da notificação confirmado")
      expect(timeline.text).to include("Para #{admin.name}")
      expect(timeline.text).to include("pelo app instalado pelo Safari")
      expect(timeline.text).to include("confirmação 201")
    end

    it "mostra redistribuicao de forma resumida para o usuario comum" do
      first_broker = create(:admin_user, tenant: admin.tenant, name: "Primeiro Corretor")
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Redistribuido", phone: "11999990003", status: "Em Atendimento")

      LeadActivity.create!(
        lead: lead,
        kind: "distributed",
        metadata: { admin_user_name: first_broker.name, rule_name: "Equipe vendas" },
        created_at: 15.minutes.ago,
        updated_at: 15.minutes.ago
      )
      LeadActivity.create!(
        lead: lead,
        kind: "distributed",
        metadata: { admin_user_name: admin.name, rule_name: "Equipe vendas" },
        created_at: 5.minutes.ago,
        updated_at: 5.minutes.ago
      )

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      timeline = Nokogiri::HTML(response.body).at_css("#leadTimelineSection")

      expect(timeline.text).to include("Lead enviado para corretor")
      expect(timeline.text).to include("Lead redistribuído")
    end

    it "agenda atividade e atualiza o painel operacional via Turbo Stream" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Em Atendimento")

      post schedule_activity_admin_lead_path(lead),
           params: {
             activity_kind: "visit",
             starts_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M"),
             ends_at: 1.day.from_now.advance(hours: 1).strftime("%Y-%m-%dT%H:%M")
           },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("pwa_operational_panel_lead_#{lead.id}", "Visita")
    end

    it "nao mostra remocao permanente para usuario que nao e admin da conta" do
      broker_profile = Profile.create!(
        tenant: admin.tenant,
        name: "Corretor #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 8_950,
        permissions: { "leads" => { "view" => true, "delete" => true, "scope" => "all" } }
      )
      broker = create(:admin_user, tenant: admin.tenant, profile: broker_profile, role: :editor)
      lead = create(:lead, tenant: admin.tenant, admin_user: broker, name: "Lead sem exclusao", status: "Em Atendimento")
      sign_out admin
      sign_in broker

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Remover permanentemente")
      expect(response.body).not_to include("Remover lead")
    end
  end

  describe "DELETE /admin/leads/:id" do
    it "permite remocao permanente apenas para admin da conta" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead removivel")

      expect {
        delete admin_lead_path(lead)
      }.to change(Lead, :count).by(-1)

      expect(response).to redirect_to(admin_leads_path)
      expect(flash[:notice]).to eq("Lead excluído com sucesso.")
    end

    it "bloqueia remocao permanente para usuario operacional" do
      broker_profile = Profile.create!(
        tenant: admin.tenant,
        name: "Operacao #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 8_951,
        permissions: { "leads" => { "view" => true, "delete" => true, "scope" => "all" } }
      )
      broker = create(:admin_user, tenant: admin.tenant, profile: broker_profile, role: :editor)
      lead = create(:lead, tenant: admin.tenant, admin_user: broker, name: "Lead protegido")
      sign_out admin
      sign_in broker

      expect {
        delete admin_lead_path(lead)
      }.not_to change(Lead, :count)

      expect(response).to redirect_to(admin_leads_path)
      expect(flash[:alert]).to eq("Você não tem permissão para excluir leads.")
    end
  end

  describe "POST /admin/leads/:id/log_contact" do
    before do
      allow_any_instance_of(Admin::LeadsController).to receive(:verified_request?).and_return(true)
    end

    it "registra anotacao do corretor na timeline do lead" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Em Atendimento")

      expect {
        post log_contact_admin_lead_path(lead), params: { contact_kind: "nota", body: "Cliente pediu simulação para amanhã." }
      }.to change { lead.activities.where(kind: "note").count }.by(1)

      expect(response).to redirect_to(admin_lead_path(lead))
      note = lead.activities.where(kind: "note").last
      expect(note.metadata).to include(
        "contact_kind" => "nota",
        "body" => "Cliente pediu simulação para amanhã.",
        "by" => admin.name,
        "admin_user_id" => admin.id
      )
      expect(note.metadata).not_to have_key("contact_result")
    end

    it "registra resultado operacional da tentativa de contato" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Em Atendimento")

      post log_contact_admin_lead_path(lead),
           params: { contact_kind: "whatsapp", contact_result: "nao_respondeu", body: "Chamou no WhatsApp e não respondeu." }

      note = lead.activities.where(kind: "note").last
      expect(note.metadata).to include(
        "contact_kind" => "whatsapp",
        "contact_result" => "nao_respondeu",
        "body" => "Chamou no WhatsApp e não respondeu."
      )
      expect(LeadActivity.unsuccessful_contact_attempts.where(id: note.id)).to exist
    end

    it "exige resultado para tentativa operacional" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Em Atendimento")

      expect {
        post log_contact_admin_lead_path(lead),
             params: { contact_kind: "whatsapp", body: "Enviei mensagem sem retorno." }
      }.not_to change { lead.activities.where(kind: "note").count }

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(flash[:alert]).to eq("Informe o resultado da tentativa de contato.")
    end

    it "nao cria anotacao vazia" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Em Atendimento")

      expect {
        post log_contact_admin_lead_path(lead), params: { contact_kind: "nota", body: "  " }
      }.not_to change { lead.activities.where(kind: "note").count }

      expect(response).to redirect_to(admin_lead_path(lead))
    end
  end

  describe "GET /admin/leads/report" do
    it "bloqueia exportacao sem permissao de relatorios de leads" do
      profile = Profile.create!(
        tenant: admin.tenant,
        name: "Perfil report bloqueado #{SecureRandom.hex(4)}",
        axis: "vertical",
        position: 9_102,
        permissions: { "leads" => { "view" => true, "scope" => "all" } }
      )
      user = create(:admin_user, tenant: admin.tenant, profile:, email: "report-bloqueado-#{SecureRandom.hex(6)}@salute.test")
      sign_in user

      get report_admin_leads_path(format: :xlsx)

      expect(response).to have_http_status(:forbidden)
    end

    it "exporta leads filtrados e inclui captacoes quando solicitado" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Cliente Relatorio", status: "Em Atendimento")
      LeadActivity.create!(
        tenant: admin.tenant,
        lead: lead,
        kind: "note",
        metadata: {
          contact_kind: "whatsapp",
          contact_result: "nao_respondeu",
          body: "Tentativa sem resposta"
        }
      )
      create(
        :habitation,
        :broker_intake,
        tenant: admin.tenant,
        admin_user: admin,
        proprietario: "Proprietario Captacao"
      )

      get report_admin_leads_path(
        format: :csv,
        attention_filter: "unsuccessful_attempts",
        include_captacoes: "1"
      )

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      csv = CSV.parse(response.body, col_sep: ";")
      expect(csv.first.first).to match(/\ARELATÓRIO LEADS \d{2}\/\d{2}\/\d{4} A \d{2}\/\d{2}\/\d{4}\z/)
      expect(csv.flatten).to include("USUÁRIO: #{admin.name}", "Cliente Relatorio", "1", "CAPTAÇÕES", "Proprietario Captacao")
    end

    it "usa a fonte comercial e dados de arquivamento da migracao externa" do
      lead = create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        name: "Lead C2S Report",
        status: "Descartado",
        origin: "C2S",
        product: "Apartamento importado",
        attribution_data: {
          "provider" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
          "lead_source" => { "name" => "Instagram Leads" },
          "channel" => { "name" => "Internet" },
          "archive_details" => { "archive_notes" => "Cliente não respondeu" },
          "product" => { "city" => "Balneário Camboriú" }
        },
        other_information: {
          "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY
        }
      )

      get report_admin_leads_path(format: :csv, q: lead.name)

      rows = CSV.parse(response.body, col_sep: ";")
      row = rows.find { |csv_row| csv_row[2] == "Lead C2S Report" }
      expect(row[5]).to eq("Instagram Leads / Internet")
      expect(row[10]).to eq("Cliente não respondeu")
      expect(row[12]).to eq("Balneário Camboriú")
    end

    it "marca legado C2S descartado sem motivo importado no relatorio" do
      lead = create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        name: "Lead C2S Legado Sem Motivo",
        status: "Descartado",
        origin: "C2S",
        other_information: { "source" => "c2s" }
      )

      get report_admin_leads_path(format: :csv, q: lead.name)

      rows = CSV.parse(response.body, col_sep: ";")
      row = rows.find { |csv_row| csv_row[2] == "Lead C2S Legado Sem Motivo" }
      expect(row[10]).to eq("Sem motivo migrado")
    end

    it "exporta fonte, motivo e cidade do payload legado C2S" do
      lead = create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        name: "Lead C2S Legado Completo",
        status: "Descartado",
        origin: "C2S",
        other_information: {
          "source" => "c2s",
          "attributes" => {
            "lead_source" => { "name" => "TikTok" },
            "channel" => { "name" => "WhatsApp" },
            "lost_reasons" => { "name" => "inactive" },
            "product" => { "city" => "Itajaí" }
          }
        }
      )

      get report_admin_leads_path(format: :csv, q: lead.name)

      rows = CSV.parse(response.body, col_sep: ";")
      row = rows.find { |csv_row| csv_row[2] == "Lead C2S Legado Completo" }
      expect(row[5]).to eq("TikTok / WhatsApp")
      expect(row[10]).to eq("Inativo")
      expect(row[12]).to eq("Itajaí")
    end

    it "exporta uma planilha Excel com layout do relatorio comercial" do
      create(:lead, tenant: admin.tenant, admin_user: admin, name: "Cliente Excel", phone: "47999998888", email: "excel@example.com", status: "Em Atendimento")

      get report_admin_leads_path(format: :xlsx)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body.b).to start_with("PK".b)
      body = response.body.dup.force_encoding(Encoding::UTF_8)
      expect(body).to include("xl/worksheets/sheet1.xml")
      expect(body).to include("A2:G3")
      expect(body).to include("RELATÓRIO LEADS")
      expect(body).to include("Nome do cliente")
      expect(body).to include("Cliente Excel")
    end
  end

  describe "GET /admin/leads/pwa_leads_page" do
    it "pagina a lista PWA em lotes de 15 por aba" do
      default_status = Lead.default_status(tenant: admin.tenant)
      22.times do |i|
        create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Todo #{i}", phone: "1199999#{format('%04d', i)}", status: default_status)
      end

      get admin_leads_path(view: "list", mobile_tab: "todo")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lead-pwa-list__loader")
      expect(response.body).to include('data-has-more="true"')

      get pwa_leads_page_admin_leads_path(mobile_tab: "todo", offset: 15), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["loaded_count"]).to eq(7)
      expect(json["total"]).to eq(22)
      expect(json["has_more"]).to eq(false)
      expect(json["next_offset"]).to eq(22)
      expect(json["html"]).to include("lead-pwa-card")
    end
  end

  describe "PATCH /admin/leads/:id/toggle_favorite" do
    it "marca e desmarca favorito do corretor logado" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Lead Favoritavel", phone: "11999999999")

      expect {
        patch toggle_favorite_admin_lead_path(lead)
      }.to change { admin.lead_favorites.where(lead: lead).count }.from(0).to(1)

      expect(response).to redirect_to(admin_lead_path(lead))

      expect {
        patch toggle_favorite_admin_lead_path(lead)
      }.to change { admin.lead_favorites.where(lead: lead).count }.from(1).to(0)
    end
  end

  describe "PATCH /admin/leads/:id" do
    before do
      allow_any_instance_of(Admin::LeadsController).to receive(:verified_request?).and_return(true)
    end

    it "atualiza status dinamico via json" do
      lead = create(:lead, status: "Novo")

      expect {
        patch admin_lead_path(lead),
              params: { lead: { status: "Em Atendimento" } },
              headers: { "ACCEPT" => "application/json" }
      }.to change(LeadAuditLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(lead.reload.status).to eq("Em Atendimento")
      expect(JSON.parse(response.body)).to include("status" => "Em Atendimento")

      log = LeadAuditLog.last
      expect(log).to have_attributes(lead_id: lead.id, admin_user_id: admin.id, action: "status_changed", source: "admin")
      expect(log.changed_fields).to include("status")
    end

    it "nao permite alterar origem pelo update administrativo" do
      lead = create(:lead, status: "Novo", origin: "webhook")

      patch admin_lead_path(lead),
            params: { lead: { origin: "manual", notes: "Contato conferido" } }

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(lead.reload.origin).to eq("webhook")
      expect(lead.notes).to eq("Contato conferido")
    end

    it "transfere o lead para outro corretor via modal (admin_user_id)" do
      other_broker = create(:admin_user, tenant: admin.tenant, email: "broker-transfer-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Novo")

      get admin_lead_path(lead)
      expect(response.body).to include("Transferir lead")

      patch admin_lead_path(lead),
            params: { lead: { admin_user_id: other_broker.id } },
            headers: { "ACCEPT" => Mime[:turbo_stream].to_s }

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(lead.reload.admin_user_id).to eq(other_broker.id)
    end

    it "transfere o corretor sem tentar voltar o lead para a etapa padrao do funil" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      default_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Novo", position: 0)
      current_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Em Atendimento", position: 1)
      next_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Proposta", position: 2)
      create(:lead_pipeline_stage_transition, tenant: admin.tenant, lead_pipeline_stage: current_stage, next_stage: next_stage)
      other_broker = create(:admin_user, tenant: admin.tenant, email: "broker-stage-transfer-#{SecureRandom.hex(4)}@salute.test")
      lead = create(
        :lead,
        tenant: admin.tenant,
        admin_user: admin,
        lead_pipeline: pipeline,
        lead_pipeline_stage: current_stage,
        status: current_stage.name
      )

      patch admin_lead_path(lead), params: { lead: { admin_user_id: other_broker.id } }

      expect(response).to redirect_to(admin_lead_path(lead))
      lead.reload
      expect(lead.admin_user_id).to eq(other_broker.id)
      expect(lead.lead_pipeline_stage_id).to eq(current_stage.id)
      expect(lead.status).to eq("Em Atendimento")
      expect(default_stage.reload.leads).to be_empty
    end

    it "permite que um corretor com escopo own transfira o PROPRIO lead" do
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      broker = create(:admin_user, profile: broker_profile, tenant: admin.tenant, email: "broker-own-transfer-#{SecureRandom.hex(4)}@salute.test")
      colleague = create(:admin_user, tenant: admin.tenant, email: "colleague-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, tenant: admin.tenant, admin_user: broker, status: "Novo")

      sign_out admin
      sign_in broker

      get admin_lead_path(lead)
      expect(response.body).to include("Transferir lead")

      patch admin_lead_path(lead), params: { lead: { admin_user_id: colleague.id } }

      expect(lead.reload.admin_user_id).to eq(colleague.id)
    end

    it "nao permite que um corretor com escopo own reatribua lead de outra pessoa" do
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      broker = create(:admin_user, profile: broker_profile, tenant: admin.tenant, email: "broker-other-transfer-#{SecureRandom.hex(4)}@salute.test")
      colleague = create(:admin_user, tenant: admin.tenant, email: "colleague-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, tenant: admin.tenant, admin_user: colleague, status: "Novo")

      sign_out admin
      sign_in broker

      patch admin_lead_path(lead), params: { lead: { admin_user_id: broker.id } }

      expect(lead.reload.admin_user_id).to eq(colleague.id)
    end

    it "salva o parecer quando o usuario e admin" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Novo")

      get admin_lead_path(lead)
      expect(response.body).to include("Parecer")

      patch admin_lead_path(lead), params: { lead: { parecer: "Cliente qualificado, alto potencial." } }

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(lead.reload.parecer).to eq("Cliente qualificado, alto potencial.")
    end

    it "nao permite que um corretor comum veja ou grave o parecer" do
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      broker = create(:admin_user, profile: broker_profile, tenant: admin.tenant, email: "broker-parecer-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, tenant: admin.tenant, admin_user: broker, status: "Novo")

      sign_out admin
      sign_in broker

      get admin_lead_path(lead)
      expect(response.body).not_to include("Parecer interno")

      patch admin_lead_path(lead), params: { lead: { parecer: "Tentativa de corretor comum" } }
      expect(lead.reload.parecer).to be_nil
    end

    it "renderiza a qualificação no card apenas quando a etapa permite" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      enabled_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Triagem")
      disabled_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Sem qualificação")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: enabled_stage, qualification_enabled: true, qualification_options: %w[qualified missing_data])
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: disabled_stage, qualification_enabled: false)
      create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: enabled_stage, status: enabled_stage.name, name: "Lead Com Qualificação")
      create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: disabled_stage, status: disabled_stage.name, name: "Lead Sem Qualificação")

      get admin_leads_path(view: "kanban", lead_pipeline_id: pipeline.id)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      enabled_card = document.at_css("article.lead-kanban-card:contains('Lead Com Qualificação')")
      disabled_card = document.at_css("article.lead-kanban-card:contains('Lead Sem Qualificação')")
      expect(enabled_card.at_css(".lead-kanban-card__qualification")).to be_present
      expect(enabled_card.text).to include("Qualificado", "Sem dados")
      expect(enabled_card.text).not_to include("Desqualificado")
      expect(disabled_card.at_css(".lead-kanban-card__qualification")).to be_nil
    end

    it "salva a qualificação do gestor/admin via json respeitando as opções da etapa" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Triagem")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: stage, qualification_enabled: true, qualification_options: %w[qualified missing_data])
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

      patch admin_lead_path(lead),
            params: { lead: { manager_qualification_status: "qualified", qualification_note: "Perfil forte" } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include(
        "qualification_status" => "qualified",
        "qualification_label" => "Qualificado",
        "qualification_divergent" => false
      )
      lead.reload
      expect(lead.manager_qualification_status).to eq("qualified")
      expect(lead.qualification_note).to eq("Perfil forte")
    end

    it "bloqueia qualificação fora das opções da etapa" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Triagem")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: stage, qualification_enabled: true, qualification_options: %w[qualified])
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

      patch admin_lead_path(lead),
            params: { lead: { manager_qualification_status: "disqualified" } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Esta qualificação não está disponível para a etapa atual.")
      expect(lead.reload.manager_qualification_status).to be_nil
    end

    it "renderiza erro de atualização via Turbo sem exigir template turbo_stream" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Triagem")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: stage, qualification_enabled: true, qualification_options: %w[qualified])
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

      patch admin_lead_path(lead),
            params: { lead: { manager_qualification_status: "disqualified" } },
            headers: { "ACCEPT" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(lead.name)
    end

    it "filtra leads com divergência de qualificação quando a etapa permite fila" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      divergence_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Conferência")
      plain_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Normal")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: divergence_stage, qualification_enabled: true, divergence_queue_enabled: true)
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: plain_stage, qualification_enabled: true, divergence_queue_enabled: false)
      create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: divergence_stage, status: divergence_stage.name, name: "Lead Divergente", broker_qualification_status: "qualified", manager_qualification_status: "disqualified")
      create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: divergence_stage, status: divergence_stage.name, name: "Lead Igual", broker_qualification_status: "qualified", manager_qualification_status: "qualified")
      create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: plain_stage, status: plain_stage.name, name: "Lead Fora da Fila", broker_qualification_status: "qualified", manager_qualification_status: "disqualified")

      get admin_leads_path(view: "kanban", lead_pipeline_id: pipeline.id, activity_filter: ["qualification_divergence"])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Divergente")
      expect(response.body).not_to include("Lead Igual")
      expect(response.body).not_to include("Lead Fora da Fila")
    end

    it "permite que o corretor atualize status do proprio lead via json" do
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      broker = create(:admin_user, profile: broker_profile, email: "broker-kanban-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, status: "Aguardando Aceite")
      lead.update_columns(admin_user_id: broker.id, status: "Aguardando Aceite")

      sign_out admin
      sign_in broker

      patch admin_lead_path(lead),
            params: { lead: { status: "Em Atendimento" } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(lead.reload.status).to eq("Em Atendimento")
      expect(JSON.parse(response.body)).to include("status" => "Em Atendimento")
    end

    it "permite que corretor transfira o PROPRIO lead mas nao altere origem por parametro forjado" do
      # Transferir é ação de dono do lead (não administrativa): corretor com
      # escopo "own" pode passar o PRÓPRIO lead pra outro colega. Origem
      # continua imutável pelo update administrativo, independente disso.
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      broker = create(:admin_user, profile: broker_profile, email: "broker-lock-#{SecureRandom.hex(4)}@salute.test")
      other_broker = create(:admin_user, profile: broker_profile, email: "broker-lock-other-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, status: "Aguardando Aceite", origin: "webhook")
      lead.update_columns(admin_user_id: broker.id, status: "Aguardando Aceite")

      sign_out admin
      sign_in broker

      patch admin_lead_path(lead),
            params: { lead: { status: "Em Atendimento", admin_user_id: other_broker.id, origin: "manual" } }

      expect(response).to redirect_to(admin_lead_path(lead))
      lead.reload
      expect(lead.status).to eq("Em Atendimento")
      expect(lead.admin_user_id).to eq(other_broker.id)
      expect(lead.origin).to eq("webhook")
    end

    it "retorna erro json claro quando o lead saiu da fila do corretor" do
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      broker = create(:admin_user, profile: broker_profile, email: "broker-stale-#{SecureRandom.hex(4)}@salute.test")
      other_broker = create(:admin_user, profile: broker_profile, email: "broker-other-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, status: "Aguardando Aceite")
      lead.update_columns(admin_user_id: other_broker.id, status: "Aguardando Aceite")

      sign_out admin
      sign_in broker

      patch admin_lead_path(lead),
            params: { lead: { status: "Em Atendimento" } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:not_found)
      expect(response).not_to be_redirect
      expect(JSON.parse(response.body)).to include(
        "error" => "lead_unavailable",
        "message" => "Este lead saiu da sua fila ou expirou. Atualize o Kanban."
      )
    end

    it "exibe histórico de alterações no detalhe do lead" do
      lead = create(:lead, status: "Novo")
      create(:lead_audit_log, lead: lead, admin_user: admin, action: "status_changed")
      LeadActivity.log!(lead:, kind: :whatsapp_in, metadata: { body: "Mensagem recebida" })

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Histórico")
      expect(response.body).to include("Histórico do Lead")
      expect(response.body).to include("alterou o status do lead")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".ax-disclosure-divider[data-controller='ax-disclosure']")).to be_present
      expect(document.css(".ax-disclosure-divider[style]")).to be_empty
    end

    it "explica quando o lead nao possui imovel especifico atrelado" do
      lead = create(:lead, status: "Novo", property_id: nil)

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Imóvel de interesse")
      expect(response.body).to include("Lead sem imóvel específico")
      expect(response.body).to include("origem geral, campanha, webhook ou atendimento")
      expect(response.body).to include("Voltar")
      expect(response.body).not_to include("name=\"lead[origin]\"")
    end

    it "exibe a imagem principal do imovel de interesse usando o resolvedor do catalogo" do
      image_url = "#{Storage::PublicPropertyPhoto.public_base_url}/spec/lead-property.jpg"
      property = create(
        :habitation,
        codigo: "LEAD-IMG",
        titulo_anuncio: "Apartamento com imagem no lead",
        pictures: [{ "url_pequena" => image_url }]
      )
      lead = create(:lead, status: "Novo", property_id: property.id)

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      image = document.at_css("img.lead-property-image")
      expect(image).to be_present
      expect(image["src"]).to eq(image_url)
      expect(image["alt"]).to eq("Imagem principal do imóvel")
      expect(document.at_css(".lead-property-summary")).to be_present
      expect(document.at_css(".lead-property-summary__media img.lead-property-image")).to be_present
      expect(document.at_css(".lead-property-summary__content")).to be_present
      expect(document.at_css(".lead-property-summary__facts")).to be_present
      expect(document.text).to include(property.preco_principal, "Código", property.codigo)
    end
  end

  describe "POST /admin/leads/:id/archive" do
    it "mostra gerenciamento de motivos de arquivamento somente para admin da conta" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin)
      admin.tenant.attribute_options.create!(context: "lead", category: "archive_reason", name: "Sem potencial")

      get admin_lead_path(lead)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('[data-attribute-manager-category-value="archive_reason"]')).to be_present

      manager_profile = admin.tenant.profiles.create!(
        name: "Gestor sem arquivo #{SecureRandom.hex(3)}",
        axis: Profile::AXES[:vertical],
        position: 20,
        active: true,
        permissions: {
          "leads" => { "view" => true, "edit" => true, "scope" => "all" },
          "catalogos" => { "manage" => true }
        }
      )
      manager = create(:admin_user, tenant: admin.tenant, profile: manager_profile, email: "lead-archive-manager-#{SecureRandom.hex(6)}@salute.test")
      sign_in manager

      get admin_lead_path(lead)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('[data-attribute-manager-category-value="archive_reason"]')).to be_nil
    end

    it "bloqueia motivo fora dos motivos permitidos da etapa" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Triagem")
      allowed_reason = admin.tenant.attribute_options.create!(context: "lead", category: "archive_reason", name: "Sem potencial #{SecureRandom.hex(4)}")
      blocked_reason = admin.tenant.attribute_options.create!(context: "lead", category: "archive_reason", name: "Motivo bloqueado #{SecureRandom.hex(4)}")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: stage, allowed_archive_reason_ids: [allowed_reason.id])
      lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

      post archive_admin_lead_path(lead),
           params: { archive_reason_id: blocked_reason.id, archive_note: "Motivo fora da etapa" }

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(flash[:alert]).to eq("Este motivo não está disponível para a etapa atual.")
      expect(lead.reload.archive_reason_id).to be_nil
      expect(lead.archived_at).to be_nil
    end
  end

  describe "POST /admin/leads/:id/schedule_activity" do
    it "agenda visita sem convite quando checkboxes não são enviados" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin)

      expect {
        post schedule_activity_admin_lead_path(lead),
             params: {
               activity_kind: "visit",
               starts_at: 1.day.from_now.iso8601,
               ends_at: 1.day.from_now.advance(hours: 1).iso8601,
               notes: "Visita sem convite"
             }
      }.to change(Appointment, :count).by(1)

      appointment = Appointment.last
      expect(response).to redirect_to(admin_lead_path(lead))
      expect(appointment.invite_via_email).to eq(false)
      expect(appointment.invite_via_whatsapp).to eq(false)
    end

    it "bloqueia agenda futura acima do limite da etapa" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Contato")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: stage, future_activity_limit_days: 2)
      lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

      travel_to Time.zone.parse("2026-08-21 10:00:00") do
        expect {
          post schedule_activity_admin_lead_path(lead),
               params: { activity_kind: "return", due_at: 4.days.from_now.iso8601, notes: "Retornar depois" }
        }.not_to change(Task, :count)
      end

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(flash[:alert]).to eq("Esta etapa permite agendar no máximo 2 dia(s) no futuro.")
    end
  end

  describe "WhatsApp no lead" do
    before do
      allow_any_instance_of(Admin::LeadsController).to receive(:verified_request?).and_return(true)
      allow_any_instance_of(Admin::LeadsController).to receive(:can?).and_call_original
      allow_any_instance_of(Admin::LeadsController).to receive(:can?).with(:view, :whatsapp_inbox).and_return(true)
      allow_any_instance_of(Admin::LeadsController).to receive(:can?).with(:manage, :whatsapp_inbox).and_return(true)
    end

    it "abre automaticamente a conversa individual no detalhe do lead quando o canal está pronto" do
      lead = create(:lead, status: "Novo", phone: "47999990000")
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(status: "connected", waba_id: "waba-lead-activation", phone_number_id: "phone-lead-activation", access_token: "token-lead-activation", presentation_enabled: true)
      PresentationCard.ensure_system_default_for(admin.tenant)
      WhatsappTemplate.create!(
        tenant: admin.tenant,
        waba_id: integration.waba_id,
        name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        language: "pt_BR",
        status: "APPROVED",
        category: "MARKETING",
        template_type: "text",
        header_format: "image",
        header_media_handle: "handle",
        body: "Olá {{1}} {{2}}",
        components: [
          { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["handle"] } },
          { "type" => "BODY", "text" => "Olá {{1}} {{2}}" }
        ]
      )

      expect {
        get admin_lead_path(lead)
      }.to change(WhatsappConversation, :count).by(1)

      conversation = WhatsappConversation.last

      expect(response).to have_http_status(:ok)
      expect(conversation.lead).to eq(lead)
      expect(conversation.contact_phone).to eq("5547999990000")
      expect(response.body).to include("Atendimento sem sair do lead")
      expect(response.body).to include("Conversa aberta, sem histórico ainda")
      expect(response.body).to include("Responder sem sair do lead")
      expect(response.body).to include("Escreva uma mensagem...")
      expect(response.body).to include("bi-lightning-charge")
      expect(response.body).to include("Templates aprovados")
      expect(response.body).to include("Apresentação")
      expect(response.body).to include("Empresa · Apresentação oficial")
      expect(response.body).to include("Empresa · Padrão")
      expect(response.body).not_to include("Abra a thread individual")
      expect(response.body).not_to include("lead-whatsapp-card__template-row")
      expect(response.body).not_to include("Ativar WhatsApp")
    end

    it "abre a thread local quando o lead tem telefone mesmo se o canal não está pronto" do
      lead = create(:lead, status: "Novo", phone: "47999990000")
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(status: "disconnected", waba_id: nil, phone_number_id: nil, access_token: nil)

      expect {
        get admin_lead_path(lead)
      }.to change(WhatsappConversation, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atendimento sem sair do lead")
      expect(response.body).to include("Conversa aberta, sem histórico ainda")
      expect(response.body).to include("Responder sem sair do lead")
      expect(response.body).not_to include("Abra a thread individual")
    end

    it "nao carrega a conversa dentro do lead quando a conta desativa essa area" do
      LeadSetting.instance(tenant: admin.tenant).update!(lead_whatsapp_conversation_enabled: false)
      lead = create(:lead, status: "Novo", phone: "47999990001")

      expect {
        get admin_lead_path(lead)
      }.not_to change(WhatsappConversation, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(lead.display_name)
      expect(response.body).not_to include('data-lead-whatsapp-panel="true"')
      expect(response.body).not_to include("Atendimento sem sair do lead")
    end

    it "mostra histórico recente quando o lead já possui thread ativa" do
      lead = create(:lead, status: "Novo", phone: "47999990009")
      conversation = WhatsappConversation.create!(tenant: admin.tenant, lead: lead, contact_phone: "5547999990009", contact_name: "Lead WhatsApp", status: "open", last_message_at: Time.current, last_message_preview: "Tudo certo")
      conversation.messages.create!(tenant: admin.tenant, direction: "inbound", body: "Olá, quero atendimento", status: "delivered")
      conversation.messages.create!(tenant: admin.tenant, direction: "outbound", body: "Perfeito, posso ajudar", status: "sent")

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atendimento sem sair do lead")
      expect(response.body).to include('data-lead-whatsapp-panel="true"')
      expect(response.body).to include("Responder sem sair do lead")
      expect(response.body).to include("Olá, quero atendimento")
      expect(response.body).to include("Perfeito, posso ajudar")
      expect(response.body).to include("Escreva uma mensagem...")
      expect(response.body).to include("Tela dedicada")
      expect(response.body).to include("wa-inbox-thread__workspace--compact")
      expect(response.body).to include("wa-inbox-composer--compact")
      expect(response.body).to include("wa-inbox-bubble--compact")
    end

    it "nao exibe falha antiga de setup no painel do lead quando ja houve envio aceito" do
      lead = create(:lead, status: "Em Atendimento", phone: "47999990010")
      conversation = WhatsappConversation.create!(tenant: admin.tenant, lead: lead, contact_phone: "5547999990010", contact_name: "Lead WhatsApp", status: "open", last_message_at: Time.current, last_message_preview: "Tudo certo")
      conversation.messages.create!(
        tenant: admin.tenant,
        direction: "outbound",
        body: "mensagem antiga que falhou",
        status: "failed",
        error_message: "Integração não configurada",
        created_at: 2.days.ago
      )
      conversation.messages.create!(
        tenant: admin.tenant,
        direction: "outbound",
        body: "mensagem aceita pela Meta",
        status: "read",
        wa_message_id: "wamid.ok",
        created_at: 1.day.ago
      )

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("mensagem aceita pela Meta")
      expect(response.body).not_to include("mensagem antiga que falhou")
      expect(response.body).not_to include("Falhou: Integração não configurada")
    end

    it "mantem o detalhe do lead navegavel quando o bloco WhatsApp falha ao carregar" do
      lead = create(:lead, status: "Novo", phone: "47999990031")
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(status: "connected", waba_id: "waba-pendente", phone_number_id: "phone-pendente", access_token: "token-pendente")
      allow_any_instance_of(Admin::LeadsController)
        .to receive(:existing_whatsapp_conversation_for)
        .and_raise(ActiveRecord::RecordInvalid.new(WhatsappConversation.new))

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WhatsApp com pendência")
      expect(response.body).to include("O bloco do WhatsApp não pôde ser carregado agora")
      expect(response.body).to include(lead.display_name)
    end

    it "nao reassocia conversa de outro lead ao abrir o detalhe" do
      lead_original = create(:lead, status: "Em Atendimento", phone: "47999990032")
      lead_atual = create(:lead, status: "Novo", phone: "47999990032")
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(status: "connected", waba_id: "waba-reuso", phone_number_id: "phone-reuso", access_token: "token-reuso", presentation_enabled: true)
      PresentationCard.ensure_system_default_for(admin.tenant)
      WhatsappTemplate.create!(
        tenant: admin.tenant,
        waba_id: integration.waba_id,
        name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        language: "pt_BR",
        status: "APPROVED",
        category: "MARKETING",
        template_type: "text",
        header_format: "image",
        header_media_handle: "handle",
        body: "Olá {{1}} {{2}}",
        components: [
          { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["handle"] } },
          { "type" => "BODY", "text" => "Olá {{1}} {{2}}" }
        ]
      )
      conversation = WhatsappConversation.create!(
        tenant: admin.tenant,
        lead: lead_original,
        contact_phone: "5547999990032",
        contact_name: "Contato em outro lead",
        status: "open"
      )
      conversation.messages.create!(
        tenant: admin.tenant,
        direction: "inbound",
        body: "Histórico antigo do WhatsApp",
        status: "delivered"
      )

      get admin_lead_path(lead_atual)

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.lead).to eq(lead_original)
      expect(conversation.contact_name).to eq("Contato em outro lead")
      expect(response.body).to include("Atendimento sem sair do lead")
      expect(response.body).not_to include("Histórico antigo do WhatsApp")
      expect(response.body).to include("Apresentação")
      expect(response.body).to include("Empresa · Apresentação oficial")
      expect(response.body).not_to include("WhatsApp com pendência")
      expect(response.body).not_to include("vinculada a outro lead")
    end

    it "reutiliza o preview de áudio dentro do lead sem autoplay" do
      lead = create(:lead, status: "Novo", phone: "47999990029")
      conversation = WhatsappConversation.create!(tenant: admin.tenant, lead: lead, contact_phone: "5547999990029", contact_name: "Lead Audio", status: "open", last_message_at: Time.current, last_message_preview: "[áudio]")
      message = conversation.messages.create!(tenant: admin.tenant, direction: "outbound", msg_type: "audio", status: "sent")
      message.media_file.attach(io: StringIO.new("fake-audio"), filename: "follow-up.mp3", content_type: "audio/mpeg")

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-bubble__surface")
      expect(response.body).to include("wa-inbox-bubble--compact")
      expect(response.body).to include("wa-audio-preview")
      expect(response.body).to include("follow-up.mp3")
      expect(response.body).to include('data-controller="wa-audio-preview"')
      expect(response.body).to include('preload="none"')
      expect(response.body).to include("data-src=")
      expect(response.body).to include('data-inline-viewer-media="true"')
      expect(response.body).not_to include("autoplay")
    end

    it "abre a thread individual do inbox para o lead" do
      lead = create(:lead, status: "Novo", phone: "47999990001")

      expect {
        post open_whatsapp_conversation_admin_lead_path(lead)
      }.to change(WhatsappConversation, :count).by(1)

      conversation = WhatsappConversation.last
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation, lead_id: lead.id))
      expect(conversation.lead).to eq(lead)
      expect(conversation.contact_phone).to eq("5547999990001")
    end

    it "prioriza BSUID ao abrir conversa quando o lead tambem tem telefone" do
      lead = create(:lead, status: "Novo", phone: "47999990004", business_scoped_user_id: "US.LEAD.4")

      expect {
        post open_whatsapp_conversation_admin_lead_path(lead)
      }.to change(WhatsappConversation, :count).by(1)

      conversation = WhatsappConversation.last
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation, lead_id: lead.id))
      expect(conversation.lead).to eq(lead)
      expect(conversation.business_scoped_user_id).to eq("US.LEAD.4")
      expect(conversation.contact_phone).to eq("5547999990004")
    end

    it "abre a thread individual do lead em modo foco quando solicitado" do
      lead = create(:lead, status: "Novo", phone: "47999990021")

      post open_whatsapp_conversation_admin_lead_path(lead), params: { workspace: "focus" }

      conversation = WhatsappConversation.last
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation, lead_id: lead.id, workspace: "focus"))
      expect(conversation.lead).to eq(lead)
    end

    it "abre conversa existente por telefone sem reassociar de outro lead" do
      lead_original = create(:lead, tenant: admin.tenant, status: "Novo", phone: "47999990022")
      lead_atual = create(:lead, tenant: admin.tenant, status: "Novo", phone: "47999990022")
      conversation = WhatsappConversation.create!(
        tenant: admin.tenant,
        lead: lead_original,
        contact_phone: "5547999990022"
      )

      post open_whatsapp_conversation_admin_lead_path(lead_atual)

      expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation, lead_id: lead_atual.id))
      expect(conversation.reload.lead).to eq(lead_original)
    end

    it "ativa o lead com template aprovado e enfileira envio" do
      allow(Whatsapp::SendMessageJob).to receive(:dispatch)
      lead = create(:lead, status: "Novo", phone: "47999990002")
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(status: "connected", waba_id: "waba-lead-activation", phone_number_id: "phone-lead-activation", access_token: "token-lead-activation")
      template = WhatsappTemplate.create!(
        tenant: admin.tenant,
        waba_id: integration.waba_id,
        name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        language: "pt_BR",
        status: "APPROVED",
        category: "MARKETING",
        template_type: "text",
        header_format: "image",
        header_media_handle: "handle",
        body: "Oi! Aqui é {{1}}, da {{2}}.",
        components: [
          { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["handle"] } },
          { "type" => "BODY", "text" => "Oi! Aqui é {{1}}, da {{2}}." }
        ]
      )

      expect {
        post activate_whatsapp_template_admin_lead_path(lead), params: { return_to: admin_lead_path(lead) }
      }.to change(WhatsappMessage, :count).by(1)

      message = WhatsappMessage.last
      expect(response).to redirect_to(admin_lead_path(lead))
      expect(message.template_name).to eq(Whatsapp::LeadActivationTemplate::TEMPLATE_NAME)
      expect(message.msg_type).to eq("template")
      expect(message.body).to include(admin.name, admin.tenant.name)
      expect(message.template_components).to be_present
      expect(Whatsapp::SendMessageJob).to have_received(:dispatch).with(message.id, tenant_id: message.tenant_id)
    end

    it "bloqueia abertura de conversa quando o lead não possui telefone ou BSUID" do
      lead = create(:lead, status: "Novo", phone: "47999990003")
      lead.update_columns(phone: nil, business_scoped_user_id: nil)

      post open_whatsapp_conversation_admin_lead_path(lead)

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(flash[:alert]).to eq("Este lead não possui telefone ou BSUID para abrir conversa no WhatsApp.")
    end
  end

  describe "GET /admin/leads/:id/attend" do
    it "permite que o primeiro corretor reivindique um lead de Shark Tank" do
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      broker = create(:admin_user, :field_agent, profile: broker_profile, email: "broker-shark-#{SecureRandom.hex(4)}@salute.test")
      rule = create(:distribution_rule, distribution_mode: :shark_tank)
      rule_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker)
      integration = WhatsappBusinessIntegration.current(broker.tenant)
      integration.save! unless integration.persisted?
      integration.update!(status: "disconnected", waba_id: nil, phone_number_id: nil, access_token: nil, inbox_attendance_enabled: false)
      LeadSetting.instance(tenant: broker.tenant).update!(push_lead_click_action: "system")
      Lead.skip_callback(:commit, :after, :route_lead)
      lead = create(:lead, status: :waiting_acceptance, admin_user: nil, distribution_rule: rule)

      sign_out admin
      sign_in broker

      get attend_admin_lead_path(lead)

      expect(response).to redirect_to(admin_lead_path(lead))
      lead.reload
      expect(lead.admin_user_id).to eq(broker.id)
      expect(lead.status).to eq(Lead.status_value(:em_atendimento))
      expect(rule_agent.reload.last_lead_received_at).to be_present
      expect(lead.activities.where(kind: "accepted").last.metadata).to include("shark_tank" => true)
    ensure
      Lead.set_callback(:commit, :after, :route_lead)
    end

    it "mostra lead ja atendido para corretor que perdeu a corrida do Shark Tank" do
      broker_profile = Tenant.default.profiles.find_by!(key: "agent")
      broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
      winner = create(:admin_user, :field_agent, profile: broker_profile, email: "broker-winner-#{SecureRandom.hex(4)}@salute.test")
      loser = create(:admin_user, :field_agent, profile: broker_profile, email: "broker-loser-#{SecureRandom.hex(4)}@salute.test")
      Lead.skip_callback(:commit, :after, :route_lead)
      lead = create(:lead, status: :waiting_acceptance, admin_user: winner)

      sign_out admin
      sign_in loser

      get attend_admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead já atendido")
      expect(lead.reload.admin_user_id).to eq(winner.id)
    ensure
      Lead.set_callback(:commit, :after, :route_lead)
    end

    it "abre a conversa interna ao atender quando o inbox WhatsApp esta habilitado" do
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(
        status: "connected",
        waba_id: "waba-attend",
        phone_number_id: "phone-attend",
        access_token: "token-attend",
        inbox_attendance_enabled: true
      )
      LeadSetting.instance(tenant: admin.tenant).update!(push_lead_click_action: "system")
      Lead.skip_callback(:commit, :after, :route_lead)
      lead = create(:lead, tenant: admin.tenant, status: :waiting_acceptance, admin_user: admin, phone: "47999990031")

      expect {
        get attend_admin_lead_path(lead)
      }.to change(WhatsappConversation, :count).by(1)

      conversation = WhatsappConversation.last
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation, lead_id: lead.id))
      expect(conversation.lead).to eq(lead)
      expect(conversation.contact_phone).to eq("5547999990031")
    ensure
      Lead.set_callback(:commit, :after, :route_lead)
    end
  end

  describe "POST /admin/leads/:id/share_properties" do
    it "gera link de selecao vinculado ao lead e mensagem pronta para WhatsApp" do
      property = create(:habitation, tenant: admin.tenant, codigo: "SEL-001", status: "Venda", exibir_no_site_flag: false)
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Maria", phone: "47999990000")
      admin.tenant.tenant_domains.create!(hostname: "app.conexaobc.com", primary_domain: true)

      post share_properties_admin_lead_path(lead),
           params: { habitation_ids: [property.id], expires_in_days: 14 },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      collection = AiPropertyShareCollection.order(:created_at).last
      expect(collection).to have_attributes(tenant_id: admin.tenant_id, admin_user_id: admin.id, lead_id: lead.id)
      expect(collection.expires_at).to be_within(5.seconds).of(14.days.from_now)
      expect(collection.habitations).to contain_exactly(property)
      expect(response.parsed_body["url"]).to eq("https://conexaobc.com#{ai_property_share_collection_path(collection.token)}")
      expect(response.parsed_body["url"]).not_to include("app.conexaobc.com")
      expect(response.parsed_body["message"]).to include("Maria", "SEL-001", response.parsed_body["url"])
      expect(response.parsed_body["whatsapp_url"]).to include("https://wa.me/5547999990000?text=")
      expect(response.parsed_body["chips_html"]).to include("SEL-001", "Enviado")
      expect(lead.activities.where(kind: "property_share")).to exist
    end

  end

  describe "GET /admin/leads/:id" do
    it "preserva status de compartilhamento dos imoveis sem renderizar inteligencia no detalhe" do
      property = create(:habitation, tenant: admin.tenant, codigo: "SENT-001")
      lead = create(:lead, tenant: admin.tenant, admin_user: admin)
      lead.property_interests.create!(tenant: admin.tenant, habitation: property)
      lead.ai_property_share_collections.create!(admin_user: admin).tap do |collection|
        collection.items.create!(habitation: property)
        collection.record!("collection_opened")
        collection.record!("property_opened", habitation: property)
        collection.record!("interest_created", lead: lead, habitation: property, admin_user: admin)
      end
      allow(InterestIntelligence::Matcher).to receive(:new).and_raise("matching should be lazy")

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SENT-001", "Interessado")
      expect(response.body).not_to include("Carregando sinais")
      expect(response.body).not_to include(interest_intelligence_admin_lead_path(lead))
    end

    it "renderiza a inteligencia de interesse no endpoint lazy" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin)
      matcher = instance_double(
        InterestIntelligence::Matcher,
        profile: { signals: {}, criteria: {}, confidence: 0 },
        profile_incomplete?: true,
        call: []
      )
      allow(InterestIntelligence::Matcher).to receive(:new).with(lead).and_return(matcher)
      frame_id = ActionView::RecordIdentifier.dom_id(lead, :interest_intelligence)

      get interest_intelligence_admin_lead_path(lead), headers: { "Turbo-Frame" => frame_id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="#{frame_id}"))
      expect(response.body).to include("Perfil ainda incompleto")
    end
  end

  describe "POST /admin/leads/:id/suggest_properties" do
    it "adiciona imoveis semelhantes aos interesses do lead" do
      lead = create(:lead, tenant: admin.tenant, admin_user: admin)
      selected = create(
        :habitation,
        tenant: admin.tenant,
        codigo: "BASE-IA",
        cidade: "Balneário Camboriú",
        bairro: "Centro",
        categoria: "Apartamento",
        dormitorios_qtd: 3,
        valor_venda_cents: 900_000_00
      )
      compatible = create(
        :habitation,
        tenant: admin.tenant,
        codigo: "MATCH-IA",
        cidade: "Balneário Camboriú",
        bairro: "Centro",
        categoria: "Apartamento",
        dormitorios_qtd: 3,
        valor_venda_cents: 930_000_00
      )
      create(
        :habitation,
        tenant: admin.tenant,
        codigo: "OUT-IA",
        cidade: "Itajaí",
        bairro: "Fazenda",
        categoria: "Terreno",
        dormitorios_qtd: 0,
        valor_venda_cents: 400_000_00
      )
      lead.property_interests.create!(tenant: admin.tenant, habitation: selected)

      post suggest_properties_admin_lead_path(lead),
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["suggestions"].pluck("id")).to include(compatible.id)
      expect(response.parsed_body["chips_html"]).to include("MATCH-IA")
      expect(lead.property_interests.where(habitation: compatible)).to exist
      expect(lead.activities.where(kind: "property_suggestions")).to exist
    end
  end
end
