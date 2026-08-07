require "rails_helper"

RSpec.describe "Admin::Leads", type: :request do
  include Devise::Test::IntegrationHelpers

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
      expect(response.body).to include("ax-leads-mobile-filter-button")
      expect(response.body).to include("admin-push-banner")
      expect(response.body).to include("<details class=\"lead-filter-collapse\">")
      expect(response.body).not_to include("<details class=\"lead-filter-collapse\" open")
      expect(response.body).to include("Filtros do funil")
      document = Nokogiri::HTML(response.body)
      expect(document.css("section.ax-filter-form.ax-leads-filters").size).to eq(1)
      expect(document.at_css('button[data-ax-modal-open="#leadPipelineCreateModal"]')).to be_present
      expect(document.at_css('button[data-ax-modal-open="#leadStatusBoardModal"]')).to be_present
      expect(document.at_css('a.ax-nav__link[href="/admin/leads?view=list"]')).to be_present
      expect(document.at_css(".ax-nav__link--group").text).to include("Funil")
      expect(document.at_css("#leadPipelineCreateModal.ax-quick-modal--lg")).to be_present
      expect(document.at_css("#leadStatusBoardModal.ax-quick-modal--lg")).to be_present
      expect(document.at_css("#leadStatusBoardModal").to_html).not_to include("Criar novo funil")
      create_modal_html = document.at_css("#leadPipelineCreateModal").to_html
      edit_modal_html = document.at_css("#leadStatusBoardModal").to_html
      expect(create_modal_html).to include("stages[0][name]", "Negócio fechado")
      expect(create_modal_html).not_to include("Defaults")
      expect(edit_modal_html).not_to include("Defaults")
      expect(edit_modal_html).not_to include("Funil em edição")
      expect(edit_modal_html).to include("Nome do funil", "Tipo de funil")
      expect(create_modal_html).to include("Nome da etapa", "Subtítulo", "Tipo da etapa")
      expect(create_modal_html).to include("Nome visível no funil", "Classificação interna usada")
      expect(create_modal_html).to include("Define a operação do funil")
      expect(document.at_css("details.lead-filter-collapse .ax-leads-filter-overlay")).to be_nil
      expect(document.at_css("details.lead-filter-collapse + .ax-leads-filter-overlay")).to be_present
      lead_card_url = document.at_css("article.lead-kanban-card[data-lead-url]")["data-lead-url"]
      expect(lead_card_url).to start_with(admin_lead_path(Lead.find_by!(name: "Cliente Kanban")))
      expect(response.body).to include("Cliente Kanban")
      expect(response.body).to include("Em Atendimento")
      expect(response.body).not_to include("data-lead-kanban-drag-handle")
    end

    it "renderiza apenas o primeiro lote de 5 leads por coluna no kanban" do
      base_time = Time.zone.parse("2026-08-06 12:00:00")
      6.times do |index|
        create(
          :lead,
          tenant: admin.tenant,
          name: "Lead Novo #{index}",
          phone: "1199999999#{index}",
          status: "Novo",
          created_at: base_time - index.minutes
        )
      end

      get admin_leads_path(view: "kanban")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      column = document.at_css('[data-lead-kanban-status="Novo"]')
      expect(column.css(".lead-kanban-card").size).to eq(5)
      expect(column.to_html).to include("Lead Novo 0", "Lead Novo 4")
      expect(column.to_html).not_to include("Lead Novo 5")
      expect(column.at_css('.lead-kanban-loader[data-lead-kanban-offset="5"][data-lead-kanban-has-more="true"]')).to be_present
    end

    it "carrega o proximo lote de uma coluna do kanban respeitando filtros" do
      base_time = Time.zone.parse("2026-08-06 12:00:00")
      6.times do |index|
        create(
          :lead,
          tenant: admin.tenant,
          name: "Lead Incremental #{index}",
          phone: "1188888888#{index}",
          status: "Novo",
          origin: "webhook",
          created_at: base_time - index.minutes
        )
      end
      create(:lead, tenant: admin.tenant, name: "Lead de Portal", status: "Novo", origin: "portal")

      get kanban_column_admin_leads_path(
        view: "kanban",
        status: "Novo",
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
      create(:lead, name: "Cliente Lista", phone: "11999999999", status: "Novo")

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lead-list-workspace")
      expect(response.body).to include("Total filtrado")
      expect(response.body.index('class="ax-metric-grid lead-list-summary"')).to be < response.body.index('<details class="lead-filter-collapse">')
      expect(Nokogiri::HTML(response.body).at_css(".ax-workspace-heading")).to be_nil
      expect(response.body).to include("WhatsApp")
      expect(response.body).not_to include("<table")
      expect(response.body).to include("Cliente Lista")
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
      expect(response.body).to include("Período")
      expect(response.body).not_to include("Lead Fora do Filtro")
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

    it "nao permite que corretor reatribua lead ou altere origem por parametro forjado" do
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
      expect(lead.admin_user_id).to eq(broker.id)
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
    end
  end

  describe "WhatsApp no lead" do
    before do
      allow_any_instance_of(Admin::LeadsController).to receive(:verified_request?).and_return(true)
      allow_any_instance_of(Admin::LeadsController).to receive(:can?).and_call_original
      allow_any_instance_of(Admin::LeadsController).to receive(:can?).with(:view, :whatsapp_inbox).and_return(true)
      allow_any_instance_of(Admin::LeadsController).to receive(:can?).with(:manage, :whatsapp_inbox).and_return(true)
    end

    it "exibe ações de conversa individual no detalhe do lead" do
      lead = create(:lead, status: "Novo", phone: "47999990000")
      template = WhatsappTemplate.create!(tenant: admin.tenant, name: "lead_boas_vindas", language: "pt_BR", status: "APPROVED", body: "Olá")

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WhatsApp individual")
      expect(response.body).to match(/(Abrir|Continuar) conversa/)
      expect(response.body).to satisfy { |body| body.include?("Enviar template") || body.include?("Responder sem sair do lead") }
      expect(response.body).to include(template.name)
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
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation))
      expect(conversation.lead).to eq(lead)
      expect(conversation.contact_phone).to eq("5547999990001")
    end

    it "abre a thread individual do lead em modo foco quando solicitado" do
      lead = create(:lead, status: "Novo", phone: "47999990021")

      post open_whatsapp_conversation_admin_lead_path(lead), params: { workspace: "focus" }

      conversation = WhatsappConversation.last
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation, workspace: "focus"))
      expect(conversation.lead).to eq(lead)
    end

    it "ativa o lead com template aprovado e enfileira envio" do
      allow(Whatsapp::SendMessageJob).to receive(:dispatch)
      lead = create(:lead, status: "Novo", phone: "47999990002")
      template = WhatsappTemplate.create!(tenant: admin.tenant, name: "lead_template", language: "pt_BR", status: "APPROVED", body: "Olá do template")

      expect {
        post activate_whatsapp_template_admin_lead_path(lead), params: { whatsapp_template_id: template.id, return_to: admin_lead_path(lead) }
      }.to change(WhatsappMessage, :count).by(1)

      message = WhatsappMessage.last
      expect(response).to redirect_to(admin_lead_path(lead))
      expect(message.template_name).to eq("lead_template")
      expect(message.msg_type).to eq("template")
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
      PushSetting.instance.update!(lead_click_action: "system")
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
  end
end
