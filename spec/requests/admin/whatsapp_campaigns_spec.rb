require "rails_helper"

RSpec.describe "Admin::WhatsappCampaigns", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin, email: "wa-campaign-#{SecureRandom.hex(6)}@salute.test") }
  let(:template) { WhatsappTemplate.create!(name: "lead_nurture", language: "pt_BR", status: "APPROVED", body: "Oi {{1}}, origem {{2}}.") }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = admin.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before do
    host! "localhost"
    sign_in admin
  end

  describe "indicadores de interação da Unitymob" do
    let(:sender) { create(:whatsapp_sender_number, tenant: admin.tenant) }
    let(:buttons) do
      admin.tenant.whatsapp_templates.create!(name: "metric-buttons", language: "pt_BR", status: "APPROVED", body: "Opções",
        buttons: {"0" => {"kind" => "quick_reply", "text" => "Visitar"}, "1" => {"kind" => "quick_reply", "text" => "Agora não"}})
    end
    let(:campaign) do
      admin.tenant.whatsapp_campaigns.create!(name: "Métrica selecionada", group_name: "Grupo selecionado", whatsapp_sender_number: sender,
        whatsapp_template: buttons, created_by: admin, status: "completed", total_recipients: 2,
        response_decisions: {buttons: buttons.interactive_buttons.map { |b| b.merge("action" => "ignore") }})
    end

    def click_message(campaign, phone, text, id)
      message = campaign.campaign_messages.find_or_create_by!(phone_number: phone) { |m| m.status = "delivered"; m.sent_at = Time.current }
      message.mark_replied!(raw_payload: {"id" => id, "type" => "button", "button" => {"text" => text}})
      message
    end

    it "usa os mesmos filtros nos indicadores e nos grupos" do
      click_message(campaign, "5511999990000", "Visitar", "click-1")
      click_message(campaign, "5511999990000", "Visitar", "click-2")
      campaign.refresh_counters!
      excluded = admin.tenant.whatsapp_campaigns.create!(name: "Fora do filtro", group_name: "Grupo excluído", whatsapp_sender_number: sender, whatsapp_template: buttons, created_by: admin, status: "draft")
      click_message(excluded, "5511999990001", "Agora não", "click-excluded")
      get admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id, status: "completed")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grupo selecionado", "Métrica selecionada", "Interações 1", "Cliques 2")
      groups = Nokogiri::HTML(response.body).css("table").find { |table| table.at_css("caption")&.text&.include?("Grupos de campanhas") }
      expect(groups.text).not_to include("Grupo excluído", "Fora do filtro")
    end

    it "separa destinatários, cliques e resultados no detalhe e na atualização ao vivo" do
      message = click_message(campaign, "5511999990000", "Visitar", "click-1")
      click_message(campaign, "5511999990000", "Agora não", "click-2")
      get status_admin_whatsapp_campaign_path(campaign)
      data = response.parsed_body
      expect(data["metrics"]).to include("interactions" => 1, "clicks" => 2, "attended" => 0, "forwarded" => 0)
      expect(data["response_cards"].map { |row| [row["label"], row["count"]] }).to contain_exactly(["Visitar", 1], ["Agora não", 1])
      expect(data["recent_interactions"].count { |row| row["kind"] == "Clique" }).to eq(2)
      get admin_whatsapp_campaign_path(campaign)
      expect(response.body).to include("Histórico de interações", "O que aconteceu na Unitymob", "Configurada:")
      expect(response.body).not_to include("viraram lead")
    end

    it "mantém o denominador das taxas consistente com as entregas" do
      click_message(campaign, "5511999990000", "Visitar", "click-1")
      campaign.campaign_messages.create!(phone_number: "5511999990001", status: "sent", sent_at: Time.current)
      get status_admin_whatsapp_campaign_path(campaign)
      data = response.parsed_body["metrics"]
      expect(data).to include("sent" => 2, "delivered" => 1, "delivery_rate" => 50.0, "read_rate" => 100.0, "reply_rate" => 100.0)
    end
  end

  describe "cobrança oficial e preço final" do
    let(:sender) { create(:whatsapp_sender_number, tenant: admin.tenant, cpl_sent_unit_price: 0.59, meta_brl_exchange_rate: 5, meta_exchange_currency: "USD") }
    let(:report) { Whatsapp::PricingAnalytics::Result.new(amount: BigDecimal("0.4375"), currency: "USD", delivered: 7, checked_at: Time.current) }

    it "exibe um único preço final com adicional e cotação sem expor a decomposição" do
      allow(Whatsapp::PricingAnalytics).to receive(:call).and_return(report)
      get pricing_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      cost = html.at_css('[aria-label="Gasto total"] .ax-metric-card__value').text
      expect(cost).to include("6,32")
      expect(response.body).to include("Ajustar parâmetros do preço", "Cotação fixa para reais")
      expect(response.body).not_to include("USD 0,44", "Valor por FLA")
    end

    it "com adicional zero apresenta somente custo Meta convertido" do
      sender.update!(cpl_sent_unit_price: 0)
      allow(Whatsapp::PricingAnalytics).to receive(:call).and_return(report)
      get pricing_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)
      expect(Nokogiri::HTML(response.body).at_css('[aria-label="Gasto total"] .ax-metric-card__value').text).to include("2,19")
    end

    it "não mostra zero ou o preço configurado como substituto do custo bloqueado" do
      allow(Whatsapp::PricingAnalytics).to receive(:call).and_return(Whatsapp::PricingAnalytics::Result.new(currency: "USD", delivered: 7, message: "Custo bloqueado por parceiro"))
      get pricing_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)
      expect(response.body).to include("Indisponível", "Custo bloqueado por parceiro")
    end

    it "recusa número de outra conta antes da API" do
      foreign = Tenant.create!(name: "Outra", slug: "price-account-#{SecureRandom.hex(3)}")
      number = create(:whatsapp_sender_number, tenant: foreign, whatsapp_business_integration: create(:whatsapp_business_integration, tenant: foreign, connected_by_admin_user: create(:admin_user, :admin, tenant: foreign)))
      expect(Whatsapp::PricingAnalytics).not_to receive(:call)
      get pricing_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: number.id)
      expect(response).to have_http_status(:not_found)
    end

    it "recusa período inválido antes da API" do
      expect(Whatsapp::PricingAnalytics).not_to receive(:call)
      get pricing_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id, pricing_started_on: "inválida")
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "recusa datas compostas sem erro interno ou consulta externa" do
      expect(Whatsapp::PricingAnalytics).not_to receive(:call)
      get pricing_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id), params: {pricing_started_on: [Date.current.iso8601]}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "carrega a cobrança separadamente sem atrasar as telas operacionais" do
      expect(Whatsapp::PricingAnalytics).not_to receive(:call)
      get admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)
      expect(response.body).to include("whatsapp_meta_pricing", "loading=\"lazy\"")
      expect(response.body).not_to include("estimativa do período", "Valor por FLA")
    end

    it "salva cotação e adicional sem refazer inscrições na Meta" do
      expect(Whatsapp::SenderNumberConnector).not_to receive(:call)
      patch admin_whatsapp_sender_number_path(sender), params: {whatsapp_sender_number: {cpl_sent_unit_price: "0,00", meta_brl_exchange_rate: "5,25", meta_exchange_currency: "USD"}}
      expect(sender.reload.cpl_sent_unit_price).to eq(0)
      expect(sender.meta_brl_exchange_rate).to eq(BigDecimal("5.25"))
      expect(response).to have_http_status(:redirect)
    end

    it "não consulta os custos globais para usuário limitado às próprias campanhas" do
      allow_any_instance_of(Admin::WhatsappCampaignsController).to receive(:visible_owner_ids).with(:whatsapp_campaigns).and_return([admin.id])
      expect(Whatsapp::PricingAnalytics).not_to receive(:call)
      get pricing_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)
      expect(response.body).to include("restrito")
    end
  end

  it "oferece somente filas ativas da conta que recebem campanhas" do
    create(:external_lead_integration, tenant: admin.tenant)
    enabled = create(:distribution_rule, tenant: admin.tenant, source_whatsapp_campaign: true, delivery_destination: "c2s")
    create(:distribution_rule, tenant: admin.tenant, source_whatsapp_campaign: false)
    create(:distribution_rule, tenant: admin.tenant, source_whatsapp_campaign: true, active: false)
    foreign = Tenant.create!(name: "Outra", slug: "campaign-picker-#{SecureRandom.hex(4)}")
    create(:distribution_rule, tenant: foreign, source_whatsapp_campaign: true)
    get new_admin_whatsapp_campaign_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    options = JSON.parse(document.at_css("[data-whatsapp-campaign-builder-distribution-rules-value]")["data-whatsapp-campaign-builder-distribution-rules-value"])
    expect(options).to eq([{ "label" => enabled.name, "value" => enabled.id }])
    destinations = JSON.parse(document.at_css("[data-whatsapp-campaign-builder-distribution-rule-destinations-value]")["data-whatsapp-campaign-builder-distribution-rule-destinations-value"])
    expect(destinations).to eq(enabled.id.to_s => "c2s")
    expect(document.at_css("[data-whatsapp-campaign-builder-target='reviewRouting']")).to be_present
  end

  it "oferece autocomplete nos selects do formulário e mantém os eventos do modelo" do
    get new_admin_whatsapp_campaign_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    selects = document.css("select[name^='whatsapp_campaign[']")
    expect(selects).not_to be_empty
    selects.each do |select|
      expect(select["data-controller"].to_s.split).to include("tom-select"), select["name"]
    end
    model = document.at_css("#whatsapp_campaign_whatsapp_template_id")
    expect(model["data-action"]).to include("previewTemplate", "refreshReview")
    expect(model["data-tom-select-create-value"]).to eq("false")
  end

  describe "GET index" do
    it "renderiza campanhas agrupadas do número selecionado sem pré-carregar associações na agregação" do
      sender = create(:whatsapp_sender_number)
      WhatsappCampaign.create!(name: "Campanha agrupada", whatsapp_template: template,
        whatsapp_sender_number: sender, group_name: "Grupo de disparos", created_by: admin)
      other_sender = create(:whatsapp_sender_number)
      WhatsappCampaign.create!(name: "Campanha de outro número", whatsapp_template: template,
        whatsapp_sender_number: other_sender, group_name: "Grupo de outro número", created_by: admin)
      get admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grupo de disparos", "Campanha agrupada")
      expect(response.body).not_to include("Campanha de outro número")
    end

    it "renderiza estado vazio compartilhado quando nao existem remetentes" do
      get admin_whatsapp_campaigns_path

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".ax-empty-state")&.text).to include("Nenhum número cadastrado")
    end

    it "renderiza a camada de selecao por numero" do
      sender = create(:whatsapp_sender_number, display_phone_number: "5511988887777", phone_number_id: "111222333444")

      get admin_whatsapp_campaigns_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Campanhas por número")
      expect(response.body).to include("Importados CSV")
      expect(response.body).to include("Descadastros WhatsApp")
      expect(response.body).to include(sender.formatted_phone)
      expect(response.body).to include("Abrir campanhas")
    end

    it "nao lista numeros desativados no seletor de remetentes" do
      sender = create(:whatsapp_sender_number, display_phone_number: "5511988887777", phone_number_id: "111222333444")
      inactive_sender = create(:whatsapp_sender_number, display_phone_number: "5511977776666", phone_number_id: "555666777888", active: false, status: "disconnected")

      get admin_whatsapp_campaigns_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(sender.formatted_phone)
      expect(response.body).not_to include(inactive_sender.formatted_phone)
    end

    it "filtra campanhas por numero de envio" do
      sender = create(:whatsapp_sender_number, display_phone_number: "5511988887777", phone_number_id: "111222333444")
      other_sender = create(:whatsapp_sender_number, display_phone_number: "5511977776666", phone_number_id: "555666777888")
      campaign = WhatsappCampaign.create!(name: "Campanha do numero", whatsapp_template: template, created_by: admin, whatsapp_sender_number: sender)
      WhatsappCampaign.create!(name: "Outra campanha", whatsapp_template: template, created_by: admin, whatsapp_sender_number: other_sender)

      get admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Campanha do numero")
      expect(response.body).not_to include("Outra campanha")
      expect(response.body).to include("Disparos WhatsApp")
      expect(response.body).to include(sender.formatted_phone)
      expect(response.body).to include("Nova campanha")
      expect(response.body).to include("Documentação")
      expect(response.body).to include(documentation_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id))
      expect(response.body).to include(admin_whatsapp_campaign_path(campaign))
      expect(response.body).to include(edit_admin_whatsapp_campaign_path(campaign))
      expect(response.body).not_to include("Workspace do número")
    end
  end

  describe "GET imported recipients" do
    it "lista destinatarios importados por CSV no menu do WhatsApp" do
      sender = create(:whatsapp_sender_number, display_phone_number: "5511988887777", phone_number_id: "111222333444")
      campaign = WhatsappCampaign.create!(
        name: "Campanha CSV",
        whatsapp_template: template,
        whatsapp_sender_number: sender,
        created_by: admin
      )
      campaign.campaign_recipients.create!(
        source: "spreadsheet",
        name: "Maria Importada",
        phone_number: "11999990000",
        email: "maria@example.com",
        origin: "csv",
        status: "Novo",
        tags: ["Premium"]
      )
      campaign.campaign_recipients.create!(
        source: "filters",
        name: "Lead por filtro",
        phone_number: "11999990001"
      )

      get admin_whatsapp_campaign_recipients_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Importados CSV")
      expect(response.body).to include("Maria Importada")
      expect(response.body).to include("maria@example.com")
      expect(response.body).to include("Premium")
      expect(response.body).not_to include("Lead por filtro")
      expect(response.body).to include(admin_whatsapp_campaign_recipients_path)
    end

    it "isola listagem e metricas de destinatarios por tenant" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant)
      campaign = WhatsappCampaign.create!(name: "CSV da conta", whatsapp_template: template, whatsapp_sender_number: sender, created_by: admin)
      campaign.campaign_recipients.create!(source: "spreadsheet", name: "Contato da conta", phone_number: "5511999990000")

      other_tenant = Tenant.create!(name: "Outra conta CSV #{SecureRandom.hex(3)}", slug: "outra-conta-csv-#{SecureRandom.hex(3)}")
      other_admin = create(:admin_user, :admin, tenant: other_tenant)
      other_template = other_admin.tenant.whatsapp_templates.create!(name: "outro_tenant", language: "pt_BR", status: "APPROVED", body: "Olá")
      other_integration = create(:whatsapp_business_integration, tenant: other_tenant, connected_by_admin_user: other_admin)
      other_sender = create(:whatsapp_sender_number, tenant: other_tenant, whatsapp_business_integration: other_integration)
      other_campaign = other_admin.tenant.whatsapp_campaigns.create!(name: "CSV externo", whatsapp_template: other_template, whatsapp_sender_number: other_sender, created_by: other_admin)
      other_campaign.campaign_recipients.create!(tenant: other_admin.tenant, source: "spreadsheet", name: "Contato externo", phone_number: "5521999990000")

      get admin_whatsapp_campaign_recipients_path

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contato da conta")
      expect(response.body).not_to include("Contato externo")
      expect(document.at_css(".ax-metric-card[aria-label='CSV no sistema'] .ax-metric-card__value")&.text).to eq("1")
      expect(document.at_css("table caption")&.text).to include("Destinatários importados")
    end
  end

  describe "GET documentation" do
    it "abre a documentacao operacional como PDF" do
      get documentation_admin_whatsapp_campaigns_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end

  describe "GET new" do
    it "renderiza builder em etapas" do
      get new_admin_whatsapp_campaign_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("whatsapp-campaign-builder")
      expect(response.body).to include("Pré-visualizar audiência")
      expect(response.body).to include("Enviar teste")
      expect(response.body).to include("Modo de envio")
      expect(response.body).to include("Enviar agora")
      expect(response.body).to include("Estimativas")
      expect(response.body).not_to include("Resposta automática")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("[role='tablist'][aria-label='Etapas da campanha']")).to be_present
      expect(document.css("[role='tab']").size).to eq(5)
      expect(document.css("[role='tabpanel']").size).to eq(5)
      expect(document.at_css("[role='progressbar'][aria-valuenow='1']")).to be_present
    end

    it "pre-seleciona template vindo do catalogo" do
      get new_admin_whatsapp_campaign_path(whatsapp_template_id: template.id)

      expect(response).to have_http_status(:ok)
      selected = Nokogiri::HTML(response.body).at_css("select#whatsapp_campaign_whatsapp_template_id option[selected]")
      expect(selected&.[]("value")).to eq(template.id.to_s)
    end
  end

  describe "GET show" do
    it "renderiza detalhe operacional da campanha" do
      sender = create(:whatsapp_sender_number)
      campaign = WhatsappCampaign.create!(
        name: "Campanha monitorada",
        whatsapp_template: template,
        whatsapp_sender_number: sender,
        group_name: "Repescagem",
        created_by: admin,
        total_recipients: 1,
        sent_count: 1,
        delivered_count: 1,
        read_count: 1,
        replied_count: 1
      )
      lead = create(:lead, admin_user: admin, phone: "(11) 99999-0000")
      campaign.campaign_messages.create!(lead: lead, phone_number: "5511999990000", status: "replied")

      get admin_whatsapp_campaign_path(campaign)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Campanha monitorada")
      expect(response.body).to include("Performance")
      expect(response.body).to include("Mensagens recentes")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("table caption")&.text).to include("Mensagens recentes da campanha Campanha monitorada")
      expect(document.css("table th[scope='col']").size).to eq(7)
      expect(document.at_css("meter[aria-label='Progresso da campanha Campanha monitorada']")).to be_present
    end

    it "exibe resumo de ocorrencias e operacoes para falhas de entrega" do
      campaign = WhatsappCampaign.create!(
        name: "Campanha com ocorrencias",
        whatsapp_template: template,
        created_by: admin,
        status: "completed"
      )
      campaign.campaign_messages.create!(
        phone_number: "5511999990001",
        status: "failed",
        failure_reason: "Envio limitado pela Meta para manter engajamento saudável (código 131049)",
        failed_at: 2.minutes.ago,
        retry_count: 1,
        next_retry_at: 6.hours.from_now
      )
      campaign.campaign_messages.create!(
        phone_number: "5511999990002",
        status: "failed",
        failure_reason: "Template paused due to low quality (132015)",
        failed_at: 1.minute.ago,
        retry_count: 1
      )

      get admin_whatsapp_campaign_path(campaign)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Operações do disparo")
      expect(response.body).to include("Reprocessar falhas")
      expect(response.body).to include("ocorrências de entrega nesta campanha")
      expect(response.body).to include("Principais motivos")
      expect(response.body).to include("Envio limitado pela Meta para manter engajamento saudável")
      expect(response.body).to include("Template pausado pela Meta por baixa qualidade")
      expect(response.body).to include("erros críticos")
    end
  end

  describe "GET status" do
    it "retorna payload para atualizar progresso em tempo real" do
      campaign = WhatsappCampaign.create!(
        name: "Campanha live",
        whatsapp_template: template,
        created_by: admin,
        status: "processing"
      )
      sent_lead = create(:lead, admin_user: admin, name: "Lead enviado", phone: "(11) 99999-0000")
      failed_lead = create(:lead, admin_user: admin, name: "Lead falhou", phone: "(11) 99999-0001")
      pending_lead = create(:lead, admin_user: admin, name: "Lead pendente", phone: "(11) 99999-0002")
      campaign.campaign_messages.create!(lead: sent_lead, phone_number: "5511999990000", status: "sent", sent_at: 6.minutes.ago)
      campaign.campaign_messages.create!(lead: failed_lead, phone_number: "5511999990001", status: "failed", failure_reason: "Contato inválido")
      campaign.campaign_messages.create!(lead: pending_lead, phone_number: "5511999990002", status: "pending")

      get status_admin_whatsapp_campaign_path(campaign), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["status"]).to eq("processing")
      expect(data["active"]).to eq(true)
      expect(data["next_poll_interval_ms"]).to eq(3000)
      expect(data["progress_percent"]).to eq(66.7)
      expect(data["pending_count"]).to eq(1)
      expect(data["metrics"]).to include("total" => 3, "sent" => 1, "failed" => 1)
      expect(data["recent_messages"].map { |message| message["recipient_name"] }).to include("Lead enviado", "Lead falhou", "Lead pendente")
      expect(data["recent_messages"].find { |message| message["recipient_name"] == "Lead enviado" }).to include(
        "status" => "delivery_unconfirmed",
        "status_label" => "Sem retorno de entrega",
        "status_tone" => "amber"
      )
    end

    it "nao mantem polling automatico quando campanha concluida apenas monitora retorno tardio de entrega" do
      campaign = WhatsappCampaign.create!(
        name: "Campanha concluida aguardando status",
        whatsapp_template: template,
        created_by: admin,
        status: "completed"
      )
      campaign.campaign_messages.create!(
        phone_number: "5511999990000",
        status: "sent",
        sent_at: 6.minutes.ago
      )

      get status_admin_whatsapp_campaign_path(campaign), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["active"]).to eq(false)
      expect(data["next_poll_interval_ms"]).to be_nil
      expect(data["recent_messages"].first).to include(
        "status" => "delivery_unconfirmed",
        "status_label" => "Sem retorno de entrega"
      )
    end

    it "inclui cards dinamicos de respostas por botao" do
      button_template = WhatsappTemplate.create!(
        name: "campanha_live_botoes",
        language: "pt_BR",
        status: "APPROVED",
        body: "Escolha.",
        buttons: { "0" => { "kind" => "quick_reply", "text" => "Saiba mais" } }
      )
      campaign = WhatsappCampaign.create!(
        name: "Campanha live botões",
        whatsapp_template: button_template,
        created_by: admin,
        status: "processing",
        response_decisions: {
          buttons: [
            {
              key: button_template.interactive_buttons.first["key"],
              text: "Saiba mais",
              kind: "quick_reply",
              action: "ignore"
            }
          ]
        }
      )
      campaign.campaign_messages.create!(phone_number: "5511999990000", status: "replied", reply_button_text: "Saiba mais")

      get status_admin_whatsapp_campaign_path(campaign), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["response_cards"].first).to include("label" => "Saiba mais", "count" => 1)
      expect(data["recent_messages"].first).to include(
        "response_status_label" => "Saiba mais",
        "response_status_note" => "Apenas registrar"
      )
    end
  end

  describe "POST preview_audience" do
    it "retorna contagem da audiencia" do
      create(:lead, name: "Lead Preview", phone: "(47) 99999-0000", origin: "site", status: "Novo", admin_user: admin)

      post preview_audience_admin_whatsapp_campaigns_path,
           params: {
             whatsapp_campaign: {
               audience_mode: "filters",
               audience_definition: {
                 conditions: {
                   "0" => { field: "status", operator: "equals", value: "Novo" },
                   "1" => { field: "origin", operator: "equals", value: "site" },
                   "2" => { field: "admin_user_id", operator: "equals", value: admin.id }
                 }
               }
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["valid_phone_count"]).to eq(1)
      expect(data["sample"].first["name"]).to eq("Lead Preview")
    end

    it "limita audiencia por filtro ao escopo hierarquico de leads do criador" do
      tenant = admin.tenant
      owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
      agent_profile = tenant.profiles.find_by!(key: "agent")
      manager_profile = Profile.create!(
        tenant: tenant,
        name: "Manager WhatsApp",
        axis: "vertical",
        position: 300,
        permissions: {
          "dashboard" => { "view" => true },
          "leads" => { "view" => true, "manage" => true, "scope" => "team" },
          "whatsapp_campaigns" => { "view" => true, "manage" => true, "scope" => "team" }
        }
      )
      owner = create(:admin_user, tenant: tenant, profile: owner_profile)
      manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner)
      subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager)
      peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner)
      create(:lead, name: "Lead da Equipe", phone: "47999990001", status: "Novo", admin_user: subordinate)
      create(:lead, name: "Lead Fora da Equipe", phone: "47999990002", status: "Novo", admin_user: peer)
      sign_in manager

      post preview_audience_admin_whatsapp_campaigns_path,
           params: {
             whatsapp_campaign: {
               audience_mode: "filters",
               whatsapp_template_id: template.id,
               audience_definition: {
                 conditions: {
                   "0" => { field: "status", operator: "equals", value: "Novo" }
                 }
               }
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["valid_phone_count"]).to eq(1)
      expect(data["sample"].map { |row| row["name"] }).to include("Lead da Equipe")
      expect(data["sample"].map { |row| row["name"] }).not_to include("Lead Fora da Equipe")
    end

    it "retorna preview de importacao CSV" do
      file = Tempfile.new(["leads", ".csv"])
      file.write("nome,telefone,email,origem,status\nMaria Silva,11999990000,maria@example.com,importacao,Novo\n")
      file.rewind

      post preview_audience_admin_whatsapp_campaigns_path,
           params: {
             whatsapp_campaign: {
               audience_mode: "spreadsheet",
               audience_file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "leads.csv")
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["ok"]).to eq(true)
      expect(data["valid_phone_count"]).to eq(1)
      expect(data["sample"].first["name"]).to eq("Maria Silva")
    ensure
      file&.close!
    end
  end

  describe "POST preview_template" do
    it "renderiza corpo do template" do
      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: template.id, template_variables: { "1" => "{{nome}}", "2" => "{{origem}}" } } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["body"]).to eq("Oi Maria Lead, origem site.")
      expect(data["preview_html"]).to include("ax-message-preview", "Oi Maria Lead, origem site.")
    end

    it "retorna botoes do template para configurar decisoes comerciais" do
      button_template = WhatsappTemplate.create!(
        name: "campanha_com_ctas",
        language: "pt_BR",
        status: "APPROVED",
        body: "Escolha uma opção.",
        buttons: {
          "0" => { "kind" => "quick_reply", "text" => "Saiba mais" },
          "1" => { "kind" => "quick_reply", "text" => "Descadastrar" }
        }
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: button_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["buttons"].map { |button| button["text"] }).to eq(["Saiba mais", "Descadastrar"])
      expect(data["buttons"].map { |button| button["action"] }).to eq(["generate_lead", "unsubscribe"])
      selects = Nokogiri::HTML.fragment(data["response_decisions_html"]).css("select")
      expect(selects.size).to eq(4)
      selects.each { |select| expect(select["data-controller"]).to eq("tom-select") }
    end

    it "retorna schema dinamico para todas as variaveis do template" do
      rich_template = WhatsappTemplate.create!(
        name: "lead_copy_superintendents",
        language: "pt_BR",
        status: "APPROVED",
        body: <<~BODY
          Fonte: {{1}}
          Nome do lead: {{2}}
          Telefone: {{3}}
          Email: {{4}}
          Infos: {{5}}
          Obs: {{6}}
          Converteu em: {{7}}

          Agente responsável: {{8}}
          Contato do agente: {{9}}
        BODY
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: rich_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["variable_count"]).to eq(9)
      expect(data["variables_schema"].map { |item| item["placeholder"] }).to eq((1..9).map { |index| "{{#{index}}}" })
      expect(data["variables_schema"].find { |item| item["index"] == 1 }["selected"]).to eq("{{origem}}")
      expect(data["variables_schema"].find { |item| item["index"] == 8 }["selected"]).to eq("{{corretor}}")
      expect(data["variables_schema"].find { |item| item["index"] == 9 }["selected"]).to eq("{{corretor_telefone}}")
    end

    it "isola contexto quando varias variaveis aparecem na mesma linha" do
      multi_template = WhatsappTemplate.create!(
        name: "reengajamento_simples_u1",
        language: "pt_BR",
        status: "APPROVED",
        body: "Olá {{1}}! Aqui é {{2}} da {{3}}. Posso te ajudar no seu atendimento?"
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: multi_template.id } },
           headers: { "ACCEPT" => "application/json" }

      data = JSON.parse(response.body)
      expect(data["variables_schema"].map { |item| item["context"] }).to eq([
        "Olá {{1}}!",
        "Aqui é {{2}} da",
        "da {{3}}."
      ])
      expect(data["variables_schema"].map { |item| item["selected"] }).to eq([
        "{{nome}}",
        "{{corretor}}",
        "{{empresa}}"
      ])
    end

    it "retorna variaveis de cabecalho e URL dinamica do template aprovado" do
      component_template = WhatsappTemplate.create!(
        name: "template_com_preambulos",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        header_format: "text",
        header_text: "Oferta para {{1}}",
        body: "Olá {{2}}, veja as condições.",
        buttons: { "0" => { "kind" => "url", "text" => "Abrir", "url" => "https://example.com/{{3}}" } },
        components: [
          { "type" => "HEADER", "format" => "TEXT", "text" => "Oferta para {{1}}" },
          { "type" => "BODY", "text" => "Olá {{2}}, veja as condições." },
          { "type" => "BUTTONS", "buttons" => [{ "type" => "URL", "text" => "Abrir", "url" => "https://example.com/{{3}}" }] }
        ]
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: component_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["variable_count"]).to eq(3)
      expect(data["variables_schema"].map { |item| item["placeholder"] }).to eq(["{{1}}", "{{2}}", "{{3}}"])
      expect(data["variables_schema"].map { |item| item["context"] }).to include(
        "Cabeçalho: Oferta para {{1}}",
        "Olá {{2}}, veja as condições.",
        "Botão 1 · URL: https://example.com/{{3}}"
      )
    end

    it "retorna midia de cabecalho para o preview do modelo" do
      media_template = WhatsappTemplate.create!(
        name: "campanha_com_imagem_preview",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        header_format: "image",
        header_media_handle: "https://cdn.example.test/header.png",
        body: "Veja a campanha.",
        components: [
          {
            "type" => "HEADER",
            "format" => "IMAGE",
            "example" => { "header_handle" => ["https://cdn.example.test/header.png"] }
          },
          { "type" => "BODY", "text" => "Veja a campanha." }
        ]
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: media_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["media"]).to include(
        "type" => "image",
        "label" => "Imagem",
        "url" => "https://cdn.example.test/header.png",
        "available" => true
      )
    end

    it "retorna audio do componente para o preview quando o template usar midia de audio" do
      audio_template = WhatsappTemplate.create!(
        name: "campanha_com_audio_preview",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        header_format: "none",
        body: "Ouça o recado.",
        components: [
          {
            "type" => "HEADER",
            "format" => "AUDIO",
            "example" => { "header_handle" => ["https://cdn.example.test/audio.mp3"] }
          },
          { "type" => "BODY", "text" => "Ouça o recado." }
        ]
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: audio_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["media"]).to include(
        "type" => "audio",
        "label" => "Áudio",
        "url" => "https://cdn.example.test/audio.mp3",
        "available" => true
      )
    end

    it "aceita PATCH quando o formulario de edicao envia _method no FormData" do
      patch preview_template_admin_whatsapp_campaigns_path,
            params: { whatsapp_campaign: { whatsapp_template_id: template.id, template_variables: { "1" => "{{nome}}", "2" => "{{origem}}" } } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["body"]).to eq("Oi Maria Lead, origem site.")
      expect(data["preview_html"]).to include("ax-message-preview", "Oi Maria Lead, origem site.")
    end
  end

  describe "POST send_test" do
    it "envia teste com componente de cabecalho de imagem quando o template exige midia" do
      sender = create(:whatsapp_sender_number)
      media_template = WhatsappTemplate.create!(
        name: "campanha_fake",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        header_format: "image",
        header_media_handle: "https://cdn.example.test/header.png",
        body: "Escolha uma das opções abaixo.",
        components: [
          {
            "type" => "HEADER",
            "format" => "IMAGE",
            "example" => { "header_handle" => ["https://cdn.example.test/header.png"] }
          },
          { "type" => "BODY", "text" => "Escolha uma das opções abaixo." }
        ]
      )
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
      allow(client).to receive(:send_template).and_return({ ok: true, message_id: "wamid.media" })

      post send_test_admin_whatsapp_campaigns_path,
           params: {
             test_phone: "5521990872427",
             whatsapp_campaign: {
               whatsapp_sender_number_id: sender.id,
               whatsapp_template_id: media_template.id
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to include("ok" => true, "message_id" => "wamid.media", "delivery_status" => "sent")
      expect(data["delivery_hint"]).to include("webhook de status")
      expect(client).to have_received(:send_template).with(
        hash_including(
          name: "campanha_fake",
          components: [
            {
              type: "header",
              parameters: [
                { type: "image", image: { link: "https://cdn.example.test/header.png" } }
              ]
            }
          ]
        )
      )
    end

    it "retorna detalhes acionaveis quando a Meta rejeita o formato do template" do
      sender = create(:whatsapp_sender_number)
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
      allow(client).to receive(:send_template).and_return(
        {
          ok: false,
          error: "(#132012) Parameter format does not match format in the created template.",
          meta_error: { code: 132012, type: "OAuthException", trace_id: "TRACE123" }
        }
      )

      post send_test_admin_whatsapp_campaigns_path,
           params: {
             test_phone: "5521990872427",
             whatsapp_campaign: {
               whatsapp_sender_number_id: sender.id,
               whatsapp_template_id: template.id,
               template_variables: { "1" => "{{nome}}", "2" => "{{origem}}" }
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      data = JSON.parse(response.body)
      expect(data["error"]).to include("#132012")
      expect(data["error_hint"]).to include("formato enviado não corresponde ao template aprovado")
      expect(data["meta_error"]).to include(
        "code" => 132012,
        "type" => "OAuthException",
        "trace_id" => "TRACE123"
      )
    end
  end

  describe "POST create" do
    %w[draft schedule start_now].each do |action|
      it "bloqueia #{action} com CSV fora do formato mesmo sem passar pela prévia" do
        file = Tempfile.new(["cabecalho-invalido", ".csv"])
        file.write("Nome do cliente,Telefone do cliente\nMaria,11999990000\n")
        file.rewind
        expect {
          post admin_whatsapp_campaigns_path, params: {
            commit_action: action,
            whatsapp_campaign: { name: "CSV inválido", whatsapp_template_id: template.id,
              audience_mode: "spreadsheet", scheduled_at: 1.day.from_now,
              audience_file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "leads.csv") }
          }
        }.not_to change(WhatsappCampaign, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Colunas não reconhecidas", "Corrija o arquivo antes de importar")
      ensure
        file&.close!
      end
    end

    it "salva rascunho" do
      sender = create(:whatsapp_sender_number)

      expect {
        post admin_whatsapp_campaigns_path, params: {
          commit_action: "draft",
          whatsapp_campaign: {
            name: "Rascunho",
            whatsapp_template_id: template.id,
            whatsapp_sender_number_id: sender.id,
            group_name: "Captação Alto Padrão",
            send_rate: 30,
            audience_filters: { status: "Novo" },
            template_variables: { "1" => "{{nome}}" }
          }
        }
      }.to change(WhatsappCampaign, :count).by(1)

      expect(WhatsappCampaign.last.status).to eq("draft")
      expect(WhatsappCampaign.last.whatsapp_sender_number).to eq(sender)
      expect(WhatsappCampaign.last.group_name).to eq("Captação Alto Padrão")
    end

    it "agenda disparo futuro" do
      future = 2.hours.from_now.change(usec: 0)

      expect {
        post admin_whatsapp_campaigns_path, params: {
          commit_action: "schedule",
          whatsapp_campaign: {
            name: "Agendada",
            whatsapp_template_id: template.id,
            send_rate: 30,
            scheduled_at: future,
            audience_filters: { status: "Novo" },
            template_variables: { "1" => "{{nome}}" }
          }
        }
      }.to have_enqueued_job(Whatsapp::CampaignStartJob)

      expect(WhatsappCampaign.last.status).to eq("scheduled")
    end

    it "bloqueia agendamento sem data e horario" do
      expect {
        post admin_whatsapp_campaigns_path, params: {
          commit_action: "schedule",
          whatsapp_campaign: {
            name: "Agendada sem data",
            whatsapp_template_id: template.id,
            send_rate: 30,
            audience_filters: { status: "Novo" },
            template_variables: { "1" => "{{nome}}" }
          }
        }
      }.not_to change(WhatsappCampaign, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Scheduled at precisa ser informado")
    end
  end

  describe "POST whatsapp sender numbers" do
    let(:gateway) { instance_double(Whatsapp::WebhookGatewayClient, register_route: Whatsapp::WebhookGatewayClient::Result.new(ok?: true, skipped?: false)) }

    before do
      allow(Whatsapp::WebhookGatewayClient).to receive(:new).and_return(gateway)
    end

    it "registra a rota com os dados atualizados do numero e da conta" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant)
      expect(Whatsapp::WebhookGatewayClient).to receive(:new) do |integration:, tenant:, target_url:|
        expect(integration.id).to eq(sender.id)
        expect(integration.waba_id).to eq("nova-waba")
        expect(tenant).to eq(admin.tenant)
        expect(target_url).to eq("http://localhost/webhooks/whatsapp")
        gateway
      end
      patch admin_whatsapp_sender_number_path(sender), params: { whatsapp_sender_number: { waba_id: "nova-waba" } }
      expect(gateway).to have_received(:register_route)
    end

    it "preserva o numero salvo e informa falha no registro da rota" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant)
      allow(gateway).to receive(:register_route).and_return(Whatsapp::WebhookGatewayClient::Result.new(ok?: false, skipped?: false, error: "Gateway indisponível"))
      patch admin_whatsapp_sender_number_path(sender), params: { whatsapp_sender_number: { label: "Atualizado" } }
      expect(sender.reload.label).to eq("Atualizado")
      expect(flash[:alert]).to include("Gateway indisponível")
    end

    it "nao registra rota quando o cadastro e invalido" do
      post admin_whatsapp_sender_numbers_path, params: { whatsapp_sender_number: { label: "Inválido" } }
      expect(gateway).not_to have_received(:register_route)
    end

    it "nao reativa rota de numero desativado ao editar" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant, active: false)
      patch admin_whatsapp_sender_number_path(sender), params: { whatsapp_sender_number: { label: "Inativo" } }
      expect(gateway).not_to have_received(:register_route)
    end

    it "reativa um numero desativado" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant, active: false, status: "disconnected")
      patch reactivate_admin_whatsapp_sender_number_path(sender)
      expect(response).to redirect_to(admin_whatsapp_integration_path)
      expect(sender.reload).to be_active
      expect(sender.status).to eq("pending")
    end

    it "adiciona numero de envio" do
      expect {
        post admin_whatsapp_sender_numbers_path, params: {
          whatsapp_sender_number: {
            label: "Relacionamento",
            display_phone_number: "5511966665555",
            phone_number_id: "999888777666",
            waba_id: "616242481017427"
          }
        }
      }.to change(WhatsappSenderNumber, :count).by(1)

      expect(response).to redirect_to(admin_whatsapp_campaigns_path(whatsapp_sender_number_id: WhatsappSenderNumber.last.id))
      expect(WhatsappSenderNumber.last.label).to eq("Relacionamento")
      expect(gateway).to have_received(:register_route)
    end

    it "atualiza parametros de CPL do numero" do
      sender = create(:whatsapp_sender_number)

      patch admin_whatsapp_sender_number_path(sender), params: {
        whatsapp_sender_number: {
          cpl_sent_unit_price: "0,75",
          cpl_fla_unit_price: "0,20"
        }
      }

      expect(response).to redirect_to(admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id))
      expect(sender.reload.cpl_sent_unit_price).to eq(0.75.to_d)
      expect(sender.cpl_fla_unit_price).to eq(0.20.to_d)
    end
  end

  describe "operacoes da campanha" do
    let(:campaign) { WhatsappCampaign.create!(name: "Operação", whatsapp_template: template, created_by: admin, status: "processing") }
    let(:lead) { create(:lead, admin_user: admin, phone: "(47) 99999-0000") }

    it "cancela pendentes" do
      campaign.campaign_messages.create!(lead: lead, phone_number: "5547999990000", status: "pending")

      post cancel_pending_admin_whatsapp_campaign_path(campaign)

      expect(response).to redirect_to(admin_whatsapp_campaign_path(campaign))
      expect(campaign.campaign_messages.last.reload.status).to eq("cancelled")
    end

    it "reprocessa falhas" do
      campaign.campaign_messages.create!(lead: lead, phone_number: "5547999990000", status: "failed", failure_reason: "HTTP 500")

      expect {
        post retry_failed_admin_whatsapp_campaign_path(campaign)
      }.to have_enqueued_job(Whatsapp::BulkSendJob)

      expect(campaign.campaign_messages.last.reload.status).to eq("pending")
    end
  end

  describe "GET /admin/whatsapp/descadastros" do
    it "lista descadastros para admin com permissao de campanhas" do
      create(:whatsapp_campaign_unsubscribe, phone_number: "5511999990000", contact_name: "Contato Teste")

      get admin_whatsapp_campaign_unsubscribes_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Descadastros WhatsApp")
      expect(response.body).to include("Contato Teste")
    end

    it "isola listagem e metricas de descadastros por tenant" do
      create(:whatsapp_campaign_unsubscribe, phone_number: "5511999990000", contact_name: "Contato da conta")
      other_tenant = Tenant.create!(name: "Outra conta opt-out #{SecureRandom.hex(3)}", slug: "outra-conta-opt-out-#{SecureRandom.hex(3)}")
      other_admin = create(:admin_user, :admin, tenant: other_tenant)
      other_integration = create(:whatsapp_business_integration, tenant: other_tenant, connected_by_admin_user: other_admin)
      other_sender = create(:whatsapp_sender_number, tenant: other_tenant, whatsapp_business_integration: other_integration)
      create(:whatsapp_campaign_unsubscribe, whatsapp_sender_number: other_sender, phone_number: "5521999990000", contact_name: "Contato externo")

      get admin_whatsapp_campaign_unsubscribes_path

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contato da conta")
      expect(response.body).not_to include("Contato externo")
      expect(document.at_css(".ax-metric-card[aria-label='Ativos no sistema'] .ax-metric-card__value")&.text).to eq("1")
      expect(document.at_css("table caption")&.text).to include("Contatos descadastrados")
    end

    it "lista e reabilita contatos descadastrados por numero" do
      sender = create(:whatsapp_sender_number, display_phone_number: "5511988887777")
      unsubscribe = create(
        :whatsapp_campaign_unsubscribe,
        whatsapp_sender_number: sender,
        phone_number: "5511999990000",
        contact_name: "Contato Teste"
      )

      get admin_whatsapp_campaign_unsubscribes_path(whatsapp_sender_number_id: sender.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Descadastros WhatsApp")
      expect(response.body).to include("Contato Teste")
      expect(response.body).to include("5511999990000")

      patch reenable_admin_whatsapp_campaign_unsubscribe_path(unsubscribe),
            params: { reenable_reason: "Teste concluído" }

      expect(response).to redirect_to(admin_whatsapp_campaign_unsubscribes_path)
      expect(unsubscribe.reload).to be_reenabled
      expect(unsubscribe.reenabled_by).to eq(admin)
      expect(unsubscribe.reenable_reason).to eq("Teste concluído")
    end
  end
end
