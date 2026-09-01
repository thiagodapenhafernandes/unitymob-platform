require "rails_helper"

RSpec.describe "Admin::WhatsappIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before do
    host! "localhost"
    sign_in admin
  end

  def current_whatsapp_integration!(attrs = {})
    WhatsappBusinessIntegration.current(admin.tenant).tap do |integration|
      integration.status ||= "connected"
      integration.waba_id ||= "616242481017427"
      integration.phone_number_id ||= "649374078254590"
      integration.access_token ||= "EAATESTTOKEN123456"
      integration.assign_attributes(attrs)
      integration.connected_by_admin_user ||= admin
      integration.save!
    end
  end

  it "exibe a tela sem duplicar paginas/forms do Meta Leads" do
    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Integração WhatsApp")
    expect(response.body).to include("WhatsApp Business API")
    expect(response.body).not_to include("Páginas e Formulários")
    expect(response.body).to include("Telefones do Site")
    expect(response.body).to include("1980983762681491")
    expect(response.body).to include("Template oficial para primeiro contato")
    expect(response.body).to include("lead_activation_default")
    expect(response.body).to include("lead_alert")
    expect(response.body).to include("lead_followup")
    expect(response.body).to include("lead_appointment_reminder")
    expect(response.body).to include("lead_task_reminder_utility")
    expect(response.body).to include("Sincronizar templates")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(".wa-tabs__item[aria-current='page']")&.text).to include("WhatsApp Business API")
    expect(document.at_css('input[type="url"][name="whatsapp_business_integration[webhook_callback_url]"]')).to be_present
    expect(document.at_css('input[type="password"][name="whatsapp_business_integration[access_token]"]')).to be_present
    expect(document.at_css('input[type="tel"][name="whatsapp_sender_number[display_phone_number]"][data-controller="phone-input"]')).to be_present
  end

  it "sincroniza templates oficiais pendentes ao abrir a tela" do
    integration = current_whatsapp_integration!(waba_id: "waba-pending-refresh")
    template = admin.tenant.whatsapp_templates.create!(
      name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      waba_id: integration.waba_id,
      language: "pt_BR",
      category: "MARKETING",
      status: "PENDING",
      template_type: "text",
      header_format: "image",
      header_media_handle: "handle",
      body: Whatsapp::LeadActivationTemplate::DEFAULT_BODY
    )
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now).with(admin.tenant.id) do
      template.update!(status: "APPROVED")
      { ok: true, synced: 1 }
    end

    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    expect(Whatsapp::SyncTemplatesJob).to have_received(:perform_now).with(admin.tenant.id)
    expect(response.body).to include("Aprovado")
    expect(template.reload.status).to eq("APPROVED")
  end

  it "nao sincroniza templates oficiais no carregamento quando nao ha pendencia" do
    integration = current_whatsapp_integration!(waba_id: "waba-approved-refresh")
    admin.tenant.whatsapp_templates.create!(
      name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      waba_id: integration.waba_id,
      language: "pt_BR",
      category: "MARKETING",
      status: "APPROVED",
      template_type: "text",
      header_format: "image",
      header_media_handle: "handle",
      body: Whatsapp::LeadActivationTemplate::DEFAULT_BODY
    )
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now)

    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    expect(Whatsapp::SyncTemplatesJob).not_to have_received(:perform_now)
  end

  it "salva rascunho do template de ativacao de lead sem enviar para a Meta" do
    integration = current_whatsapp_integration!(waba_id: "waba-activation")

    patch lead_activation_template_admin_whatsapp_integration_path, params: {
      whatsapp_template: {
        category: "MARKETING",
        body: "Oi! Aqui é {{1}}, da {{2}}. Podemos conversar por aqui?",
        footer_text: "Conexão BC",
        allow_category_change: "1"
      }
    }

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-activation-template"))
    template = admin.tenant.whatsapp_templates.find_by!(name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME)
    expect(template.waba_id).to eq(integration.waba_id)
    expect(template.status).to eq("DRAFT")
    expect(template.header_format).to eq("image")
    expect(template.body).to include("{{1}}", "{{2}}")
  end

  it "envia o template de ativacao para aprovacao pela Meta" do
    integration = current_whatsapp_integration!(
      waba_id: "waba-activation-submit",
      phone_number_id: "phone-activation-submit",
      access_token: "token-activation-submit"
    )
    template = Whatsapp::LeadActivationTemplate.for(tenant: admin.tenant, integration: integration)
    template.header_media_handle = "header-handle"
    template.save!
    allow(Whatsapp::TemplateSubmission).to receive(:call) do |template:, client:|
      template.update!(status: "PENDING", meta_id: "tpl-activation")
      { ok: true, template: template }
    end

    post submit_lead_activation_template_admin_whatsapp_integration_path

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-activation-template"))
    expect(template.reload.status).to eq("PENDING")
    expect(Whatsapp::TemplateSubmission).to have_received(:call)
  end

  it "sincroniza antes de enviar o template de ativacao e nao reenvia quando ja esta aprovado na WABA atual" do
    integration = current_whatsapp_integration!(waba_id: "waba-activation-current-approved")
    admin.tenant.whatsapp_templates.create!(
      name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      waba_id: integration.waba_id,
      language: "pt_BR",
      category: "MARKETING",
      status: "APPROVED",
      template_type: "text",
      header_format: "image",
      header_media_handle: "handle",
      body: Whatsapp::LeadActivationTemplate::DEFAULT_BODY
    )
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now).with(admin.tenant.id).and_return({ ok: true, synced: 1 })
    allow(Whatsapp::TemplateSubmission).to receive(:call)

    post submit_lead_activation_template_admin_whatsapp_integration_path

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-activation-template"))
    expect(Whatsapp::SyncTemplatesJob).to have_received(:perform_now).with(admin.tenant.id)
    expect(Whatsapp::TemplateSubmission).not_to have_received(:call)
  end

  it "envia o template de ativacao na WABA atual reaproveitando imagem aprovada de WABA anterior" do
    current_integration = current_whatsapp_integration!(
      waba_id: "waba-activation-current",
      phone_number_id: "phone-activation-current",
      access_token: "token-activation-current"
    )
    previous_template = admin.tenant.whatsapp_templates.create!(
      name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      waba_id: "waba-activation-old",
      language: "pt_BR",
      category: "MARKETING",
      status: "APPROVED",
      template_type: "text",
      header_format: "image",
      header_media_handle: "old-handle",
      body: Whatsapp::LeadActivationTemplate::DEFAULT_BODY,
      footer_text: "Atendimento"
    )
    previous_template.header_media_file.attach(
      io: StringIO.new("fake-template-image"),
      filename: "apresentacao.jpg",
      content_type: "image/jpeg"
    )
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now).with(admin.tenant.id).and_return({ ok: true, synced: 0 })
    allow(Whatsapp::TemplateSubmission).to receive(:call) do |template:, client:|
      expect(template.waba_id).to eq(current_integration.waba_id)
      expect(template.header_media_file).to be_attached
      expect(template.header_media_file.blob).to eq(previous_template.header_media_file.blob)
      template.update!(status: "PENDING", meta_id: "tpl-activation-current")
      { ok: true, template: template }
    end

    post submit_lead_activation_template_admin_whatsapp_integration_path

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-activation-template"))
    expect(Whatsapp::TemplateSubmission).to have_received(:call)
    template = admin.tenant.whatsapp_templates.find_by!(name: "lead_activation_default", waba_id: current_integration.waba_id)
    expect(template.status).to eq("PENDING")
  end

  it "envia o template lead_alert para analise da Meta" do
    integration = current_whatsapp_integration!(
      waba_id: "waba-lead-alert-submit",
      phone_number_id: "phone-lead-alert-submit",
      access_token: "token-lead-alert-submit"
    )
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now).with(admin.tenant.id).and_return({ ok: true, synced: 0 })
    allow(Whatsapp::TemplateSubmission).to receive(:call) do |template:, client:|
      expect(template.name).to eq("lead_alert")
      expect(template.category).to eq("UTILITY")
      expect(template.header_format).to eq("none")
      expect(template.footer_text).to be_nil
      expect(template.body).to eq(Whatsapp::LeadAlertTemplate::DEFAULT_BODY)
      expect(template.meta_create_payload[:components].pluck(:type)).to eq(["BODY"])
      template.update!(status: "PENDING", meta_id: "tpl-lead-alert")
      { ok: true, template: template }
    end

    post submit_lead_alert_template_admin_whatsapp_integration_path

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-alert-template"))
    template = admin.tenant.whatsapp_templates.find_by!(name: "lead_alert", waba_id: integration.waba_id)
    expect(template.status).to eq("PENDING")
    expect(Whatsapp::TemplateSubmission).to have_received(:call)
  end

  it "nao reenvia lead_alert quando o sync ja encontra template aprovado" do
    integration = current_whatsapp_integration!(waba_id: "waba-lead-alert-approved")
    admin.tenant.whatsapp_templates.create!(
      name: "lead_alert",
      waba_id: integration.waba_id,
      language: "pt_BR",
      category: "UTILITY",
      status: "APPROVED",
      template_type: "text",
      header_format: "none",
      body: Whatsapp::LeadAlertTemplate::DEFAULT_BODY
    )
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now).with(admin.tenant.id).and_return({ ok: true, synced: 1 })
    allow(Whatsapp::TemplateSubmission).to receive(:call)

    post submit_lead_alert_template_admin_whatsapp_integration_path

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-alert-template"))
    expect(Whatsapp::TemplateSubmission).not_to have_received(:call)
  end

  it "envia template oficial de retomada para analise da Meta" do
    integration = current_whatsapp_integration!(
      waba_id: "waba-lead-followup-submit",
      phone_number_id: "phone-lead-followup-submit",
      access_token: "token-lead-followup-submit"
    )
    definition = Whatsapp::LeadConversationTemplates.find("lead_followup")
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now).with(admin.tenant.id).and_return({ ok: true, synced: 0 })
    allow(Whatsapp::TemplateSubmission).to receive(:call) do |template:, client:|
      expect(template.name).to eq("lead_followup")
      expect(template.category).to eq("MARKETING")
      expect(template.header_format).to eq("none")
      expect(template.footer_text).to be_nil
      expect(template.body).to eq(definition.body)
      expect(template.meta_create_payload[:components].pluck(:type)).to eq(["BODY"])
      template.update!(status: "PENDING", meta_id: "tpl-lead-followup")
      { ok: true, template: template }
    end

    post submit_lead_conversation_template_admin_whatsapp_integration_path,
         params: { template_name: "lead_followup" }

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-conversation-templates"))
    template = admin.tenant.whatsapp_templates.find_by!(name: "lead_followup", waba_id: integration.waba_id)
    expect(template.status).to eq("PENDING")
    expect(Whatsapp::TemplateSubmission).to have_received(:call)
  end

  it "nao reenvia template oficial de conversa quando o sync ja encontra aprovado" do
    integration = current_whatsapp_integration!(waba_id: "waba-lead-followup-approved")
    definition = Whatsapp::LeadConversationTemplates.find("lead_followup")
    admin.tenant.whatsapp_templates.create!(
      name: definition.name,
      waba_id: integration.waba_id,
      language: "pt_BR",
      category: definition.category,
      status: "APPROVED",
      template_type: "text",
      header_format: "none",
      body: definition.body
    )
    allow(Whatsapp::SyncTemplatesJob).to receive(:perform_now).with(admin.tenant.id).and_return({ ok: true, synced: 1 })
    allow(Whatsapp::TemplateSubmission).to receive(:call)

    post submit_lead_conversation_template_admin_whatsapp_integration_path,
         params: { template_name: "lead_followup" }

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-conversation-templates"))
    expect(Whatsapp::SyncTemplatesJob).to have_received(:perform_now).with(admin.tenant.id)
    expect(Whatsapp::TemplateSubmission).not_to have_received(:call)
  end

  it "bloqueia edicao do template de ativacao depois de aprovado" do
    integration = current_whatsapp_integration!(waba_id: "waba-activation-approved")
    template = admin.tenant.whatsapp_templates.create!(
      name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      waba_id: integration.waba_id,
      language: "pt_BR",
      category: "MARKETING",
      status: "APPROVED",
      template_type: "text",
      header_format: "image",
      header_media_handle: "handle",
      body: "Texto aprovado {{1}} {{2}}"
    )

    patch lead_activation_template_admin_whatsapp_integration_path, params: {
      whatsapp_template: { body: "Texto alterado {{1}} {{2}}" }
    }

    expect(response).to redirect_to(admin_whatsapp_integration_path(anchor: "lead-activation-template"))
    expect(template.reload.body).to eq("Texto aprovado {{1}} {{2}}")
  end

  it "redireciona a antiga aba de forms para Meta Leads" do
    get admin_whatsapp_integration_path(tab: "forms")

    expect(response).to redirect_to(admin_meta_integrations_path)
  end

  it "mantem webhook proprio nos campos e exibe nota do webhook global quando configurado" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_PUBLIC_URL").and_return("https://webhooks.unitymob.com.br/webhooks/whatsapp")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_URL").and_return("https://webhooks.unitymob.com.br")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_VERIFY_TOKEN").and_return("gateway-verify-token")

    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    callback = document.at_css('input[type="url"][name="whatsapp_business_integration[webhook_callback_url]"]')
    token = document.at_css('input[name="whatsapp_business_integration[webhook_verify_token]"]')

    expect(callback["placeholder"]).to eq("http://localhost/webhooks/whatsapp")
    expect(callback["value"]).to eq("http://localhost/webhooks/whatsapp")
    expect(token["value"]).not_to eq("gateway-verify-token")
    expect(response.body).to include("Webhook global Unitymob")
    expect(response.body).to include("https://webhooks.unitymob.com.br/webhooks/whatsapp")
    expect(response.body).to include("gateway-verify-token")
  end

  it "renderiza o prefixo semântico dos telefones do site" do
    get admin_whatsapp_integration_path(tab: "site_phones")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Telefones dos formulários do site")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(".ax-input-group__icon--whatsapp")).to be_present
    expect(document.at_css(".wa-tabs__item[aria-current='page']")&.text).to include("Telefones do Site")
    expect(document.css(".wa-form [style]")).to be_empty
    expect(document.at_css('input[type="tel"][name="whatsapp_business_integration[sale_whatsapp_number]"][data-controller="phone-input"]')).to be_present
  end

  it "inclui metadados dos placeholders para mapear variaveis ao selecionar template de notificacao" do
    integration = current_whatsapp_integration!(waba_id: "waba-auto-map")
    template = admin.tenant.whatsapp_templates.create!(
      name: "lead_distribution_auto_map",
      waba_id: integration.waba_id,
      language: "pt_BR",
      category: "UTILITY",
      status: "APPROVED",
      template_type: "text",
      header_format: "none",
      body: "Lead {{1}} veio de {{2}}. Telefone {{3}}."
    )

    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    option = document.at_css("select[data-whatsapp-integration-target='notificationTemplateSelect'] option[value='#{template.id}']")
    map = document.at_css("[data-whatsapp-integration-target='notificationVariableMap']")
    references = JSON.parse(option["data-variable-references"])

    expect(option).to be_present
    expect(map).to be_present
    expect(references.map { |item| item["index"] }).to eq([1, 2, 3])
    expect(references.map { |item| item["context"] }.join(" ")).to include("Lead", "Telefone")
    expect(JSON.parse(map["data-variable-sources"]).to_h.values).to include("lead_phone_or_link")
  end

  it "oferece o numero integrado para campanhas quando ainda nao existe sender cadastrado" do
    integration = current_whatsapp_integration!
    client = instance_double(Whatsapp::CloudClient, phone_info: {
      ok: true,
      data: {
        "display_phone_number" => "+55 47 3311-1067",
        "verified_name" => "Salute Imóveis",
        "quality_rating" => "GREEN"
      }
    })
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Usar número integrado")
    expect(response.body).to include("Adicionar número")
  end

  it "disponibiliza o numero integrado na lista de campanhas" do
    integration = current_whatsapp_integration!
    client = instance_double(Whatsapp::CloudClient, phone_info: {
      ok: true,
      data: {
        "display_phone_number" => "+55 47 3311-1067",
        "verified_name" => "Salute Imóveis",
        "quality_rating" => "GREEN"
      }
    })
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    expect {
      post use_current_number_for_campaigns_admin_whatsapp_integration_path
    }.to change(WhatsappSenderNumber, :count).by(1)

    sender = admin.tenant.whatsapp_sender_numbers.find_by!(phone_number_id: integration.phone_number_id)
    expect(response).to redirect_to(admin_whatsapp_integration_path)
    expect(sender).to be_active
    expect(sender.label).to eq("Salute Imóveis")
    expect(sender.display_phone_number).to eq("554733111067")
    expect(sender.waba_id).to eq(integration.waba_id)
    expect(sender.quality_rating).to eq("GREEN")
  end

  it "reativa o sender do numero integrado quando ele ja existia desativado" do
    integration = current_whatsapp_integration!
    sender = create(
      :whatsapp_sender_number,
      tenant: admin.tenant,
      whatsapp_business_integration: integration,
      phone_number_id: integration.phone_number_id,
      display_phone_number: "554733111067",
      label: "Principal antigo",
      active: false,
      status: "disconnected"
    )
    client = instance_double(Whatsapp::CloudClient, phone_info: { ok: false, error: "indisponível" })
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    expect {
      post use_current_number_for_campaigns_admin_whatsapp_integration_path
    }.not_to change(WhatsappSenderNumber, :count)

    expect(response).to redirect_to(admin_whatsapp_integration_path)
    expect(sender.reload).to be_active
    expect(sender.status).to eq("connected")
    expect(sender.label).to eq("Principal antigo")
  end

  it "exibe acao para registrar o numero quando a integracao esta pronta" do
    integration = current_whatsapp_integration!
    client = instance_double(
      Whatsapp::CloudClient,
      phone_info: {
        ok: true,
        data: {
          "display_phone_number" => "+55 47 9142-7176",
          "verified_name" => "Conexão BC",
          "quality_rating" => "UNKNOWN",
          "code_verification_status" => "NOT_VERIFIED",
          "platform_type" => "CLOUD_API",
          "name_status" => "APPROVED",
          "account_mode" => "LIVE",
          "status" => "CONNECTED",
          "official_business_account" => { "status" => "APPROVED" },
          "throughput" => { "level" => "STANDARD" }
        }
      }
    )
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    form = document.at_css("form[action='#{register_phone_number_admin_whatsapp_integration_path}']")
    expect(form).to be_present
    expect(form.at_css("input[name='pin'][maxlength='6']")).to be_present
    expect(form.text).to include("Registrar número")
    expect(document.text).to include("Qualidade pendente")
    expect(document.text).to include("Nome aprovado")
    expect(document.text).to include("Conta comercial oficial")
    expect(document.text).to include("Modo da conta")
    expect(document.text).to include("Produção")
    expect(document.text).to include("Throughput")
    expect(document.text).to include("STANDARD")
    expect(document.text).not_to include("UNKNOWN")
  end

  it "mostra numero registrado e oculta PIN quando a Meta confirma verificacao" do
    integration = current_whatsapp_integration!
    client = instance_double(
      Whatsapp::CloudClient,
      phone_info: {
        ok: true,
        data: {
          "display_phone_number" => "+55 47 9142-7176",
          "verified_name" => "Conexão BC",
          "quality_rating" => "GREEN",
          "code_verification_status" => "VERIFIED"
        }
      }
    )
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(response.body).to include("Número registrado na Meta")
    expect(response.body).to include("Registrado")
    expect(document.at_css("form[action='#{register_phone_number_admin_whatsapp_integration_path}']")).to be_nil
    expect(response.body).not_to include("739184")
  end

  it "registra o numero na Meta e sincroniza como remetente das notificacoes" do
    integration = current_whatsapp_integration!(
      phone_number_id: "phone-register",
      waba_id: "waba-register"
    )
    client = instance_double(
      Whatsapp::CloudClient,
      register_phone_number: { ok: true, status: 200, data: { "success" => true } },
      phone_info: {
        ok: true,
        data: {
          "display_phone_number" => "+55 47 9142-7176",
          "verified_name" => "Conexão BC",
          "quality_rating" => "GREEN"
        }
      }
    )
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    post register_phone_number_admin_whatsapp_integration_path, params: { pin: "123456" }

    expect(response).to redirect_to(admin_whatsapp_integration_path)
    expect(client).to have_received(:register_phone_number).with(pin: "123456")
    sender = admin.tenant.whatsapp_sender_numbers.find_by!(phone_number_id: "phone-register")
    expect(sender).to be_active
    expect(sender).to be_use_for_notifications
    expect(sender.waba_id).to eq("waba-register")
    expect(sender.display_phone_number).to eq("5547991427176")
  end

  it "mostra erro quando a Meta recusa o registro do numero" do
    integration = current_whatsapp_integration!
    client = instance_double(
      Whatsapp::CloudClient,
      register_phone_number: { ok: false, error: "(#133010) Account not registered" },
      phone_info: { ok: false, error: "indisponível" }
    )
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    post register_phone_number_admin_whatsapp_integration_path, params: { pin: "123456" }

    expect(response).to redirect_to(admin_whatsapp_integration_path)
    follow_redirect!
    expect(response.body).to include("(#133010) Account not registered")
  end

  it "exibe e salva telefones do site por tipo de negociacao" do
    get admin_whatsapp_integration_path(tab: "site_phones")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Telefones dos formulários do site")

    patch phone_settings_admin_whatsapp_integration_path, params: {
      whatsapp_business_integration: {
        default_whatsapp_number: "554733111067",
        sale_whatsapp_number: "5547991111111",
        rent_whatsapp_number: "5547992222222",
        sale_rent_whatsapp_number: "5547993333333",
        sale_requires_lead_form: "1",
        rent_requires_lead_form: "0",
        sale_rent_requires_lead_form: "1"
      }
    }

    expect(response).to redirect_to(admin_whatsapp_integration_path(tab: "site_phones"))
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration.phone_for("sale")).to eq("5547991111111")
    expect(integration.phone_for("rent")).to eq("5547992222222")
    expect(integration.requires_form_for?("rent")).to be(false)
  end

  it "salva a conexao quando o embedded signup finaliza" do
    integration = current_whatsapp_integration!(
      waba_id: "old-waba",
      phone_number_id: "old-phone",
      business_id: "old-business"
    )
    stale_sender = create(
      :whatsapp_sender_number,
      tenant: admin.tenant,
      whatsapp_business_integration: integration,
      phone_number_id: "old-phone",
      waba_id: "old-waba",
      active: true,
      use_for_notifications: true
    )
    Rails.cache.write("whatsapp_phone_info/#{integration.id}", { number: "+55 47 0000-0000" })
    service = instance_double(Facebook::WhatsappEmbeddedSignupService, exchange_code!: {
      "access_token" => "business-token",
      "expires_in" => 3600
    })
    client = instance_double(
      Whatsapp::CloudClient,
      phone_info: {
        ok: true,
        data: {
          "display_phone_number" => "+55 47 9142-7176",
          "verified_name" => "Conexão BC",
          "quality_rating" => "GREEN"
        }
      },
      subscribe_app: { ok: true, status: 200, data: { "success" => true } }
    )
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_SYSTEM_USER_TOKEN").and_return(nil)
    allow(Facebook::WhatsappEmbeddedSignupService).to receive(:new).with(code: "code-123").and_return(service)
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow(Whatsapp::WebhookGatewayClient).to receive(:public_webhook_url).and_return(nil)
    gateway = instance_double(Whatsapp::WebhookGatewayClient, register_route: Whatsapp::WebhookGatewayClient::Result.new(ok?: true, skipped?: false))
    allow(Whatsapp::WebhookGatewayClient).to receive(:new).and_return(gateway)

    post embedded_signup_callback_admin_whatsapp_integration_path, params: {
      code: "code-123",
      event: "FINISH",
      session_info: {
        waba_id: "616242481017427",
        phone_number_id: "649374078254590",
        business_id: "business-1"
      }
    }, as: :json

    expect(response).to have_http_status(:ok)
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration).to be_connected
    expect(integration.access_token).to eq("business-token")
    expect(integration.connected_by_admin_user).to eq(admin)
    expect(Whatsapp::CloudClient).to have_received(:new).with(integration).twice
    expect(stale_sender.reload).not_to be_active
    sender = admin.tenant.whatsapp_sender_numbers.find_by!(phone_number_id: "649374078254590")
    expect(sender).to be_active
    expect(sender).to be_use_for_notifications
    expect(sender.waba_id).to eq("616242481017427")
    expect(sender.display_phone_number).to eq("5547991427176")
    expect(sender.quality_rating).to eq("GREEN")
    expect(Rails.cache.read("whatsapp_phone_info/#{integration.id}")).to be_nil
    expect(client).to have_received(:subscribe_app)
    expect(gateway).to have_received(:register_route)
  end

  it "prefere o token permanente do system user quando configurado" do
    service = instance_double(Facebook::WhatsappEmbeddedSignupService, exchange_code!: {
      "access_token" => "embedded-signup-token",
      "expires_in" => 3600
    })
    client = instance_double(
      Whatsapp::CloudClient,
      phone_info: { ok: false, error: "indisponível" },
      subscribe_app: { ok: true, status: 200, data: { "success" => true } }
    )
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_SYSTEM_USER_TOKEN").and_return("system-user-token")
    allow(Facebook::WhatsappEmbeddedSignupService).to receive(:new).with(code: "code-123").and_return(service)
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow_any_instance_of(Whatsapp::WebhookGatewayClient).to receive(:register_route).and_return(Whatsapp::WebhookGatewayClient::Result.new(ok?: false, skipped?: true))

    post embedded_signup_callback_admin_whatsapp_integration_path, params: {
      code: "code-123",
      event: "FINISH",
      session_info: {
        waba_id: "616242481017427",
        phone_number_id: "649374078254590",
        business_id: "business-1"
      }
    }, as: :json

    expect(response).to have_http_status(:ok)
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration.access_token).to eq("system-user-token")
    expect(integration.token_expires_at).to be_nil
  end

  it "mantem conectado e registra aviso quando a assinatura da WABA falha" do
    service = instance_double(Facebook::WhatsappEmbeddedSignupService, exchange_code!: {
      "access_token" => "business-token",
      "expires_in" => 3600
    })
    client = instance_double(
      Whatsapp::CloudClient,
      phone_info: { ok: false, error: "indisponível" },
      subscribe_app: {
        ok: false,
        error: "Missing permission",
        meta_error: { code: 200 }
      }
    )
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_SYSTEM_USER_TOKEN").and_return(nil)
    allow(Facebook::WhatsappEmbeddedSignupService).to receive(:new).with(code: "code-123").and_return(service)
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow_any_instance_of(Whatsapp::WebhookGatewayClient).to receive(:register_route).and_return(Whatsapp::WebhookGatewayClient::Result.new(ok?: false, skipped?: true))

    post embedded_signup_callback_admin_whatsapp_integration_path, params: {
      code: "code-123",
      event: "FINISH",
      session_info: {
        waba_id: "616242481017427",
        phone_number_id: "649374078254590",
        business_id: "business-1"
      }
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["message"]).to include("não foi possível assinar")
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration).to be_connected
    expect(integration.last_error_code).to eq("200").or eq(200)
    expect(integration.last_error_message).to include("Missing permission")
  end

  it "registra cancelamento sem salvar token" do
    post embedded_signup_callback_admin_whatsapp_integration_path, params: {
      event: "CANCEL",
      session_info: {
        current_step: "PHONE_NUMBER_SETUP",
        session_id: "session-1"
      }
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration.status).to eq("canceled")
    expect(integration.last_error_message).to eq("Conexão cancelada na Meta em PHONE_NUMBER_SETUP.")
    expect(integration.access_token).to be_blank
  end

  it "aceita o payload embrulhado pelo wrapper de parametros do Rails" do
    post embedded_signup_callback_admin_whatsapp_integration_path, params: {
      whatsapp_integration: {
        event: "ERROR",
        session_info: {}
      }
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["message"]).to include("Meta retornou erro")
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration.status).to eq("failed")
    expect(integration.last_error_message).to include("Meta retornou erro")
    expect(integration.signup_payload).to eq("event" => "ERROR", "session_info" => {})
  end

  it "nao marca como conectado quando a Meta nao retorna WABA e telefone" do
    post embedded_signup_callback_admin_whatsapp_integration_path, params: {
      code: "code-123",
      event: "FINISH",
      session_info: {
        business_id: "business-1"
      }
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration.status).to eq("failed")
    expect(integration.last_error_message).to include("WABA ID")
    expect(integration.access_token).to be_blank
  end

  it "desconecta a integracao atual" do
    create(:whatsapp_business_integration)

    delete disconnect_admin_whatsapp_integration_path

    expect(response).to redirect_to(admin_whatsapp_integration_path)
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    expect(integration.status).to eq("disconnected")
    expect(integration.access_token).to be_nil
  end

  it "falha o diagnostico quando nao ha app inscrito na WABA" do
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    integration.update!(
      status: "connected",
      access_token: "business-token",
      phone_number_id: "649374078254590",
      waba_id: "616242481017427"
    )
    client = instance_double(
      Whatsapp::CloudClient,
      configured?: true,
      phone_info: { ok: true, data: { "display_phone_number" => "+55 47 99999-9999" } },
      subscribed_apps: { ok: true, data: { "data" => [] } }
    )
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    post test_connection_admin_whatsapp_integration_path, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["ok"]).to be(false)
    expect(response.parsed_body.dig("send", "ok")).to be(true)
    expect(response.parsed_body.dig("receive", "ok")).to be(false)
    expect(response.parsed_body.dig("receive", "error")).to include("não está inscrito na WABA")
  end

  it "registra a mensagem do envio de teste para acompanhar entrega por webhook" do
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    integration.update!(
      status: "connected",
      access_token: "business-token",
      phone_number_id: "649374078254590",
      waba_id: "616242481017427"
    )
    client = instance_double(Whatsapp::CloudClient, send_text: { ok: true, message_id: "wamid.TEST-DELIVERY" })
    allow(Whatsapp::CloudClient).to receive(:new).with(integration).and_return(client)

    expect {
      post send_test_admin_whatsapp_integration_path, params: { to: "(47) 99999-0000" }, as: :json
    }.to change(WhatsappMessage, :count).by(1)

    expect(response).to have_http_status(:ok)
    message = WhatsappMessage.last
    expect(message).to have_attributes(
      tenant_id: admin.tenant_id,
      direction: "outbound",
      status: "sent",
      wa_message_id: "wamid.TEST-DELIVERY"
    )
    expect(response.parsed_body["status_url"]).to include("message_id=#{message.id}")
  end

  it "retorna o status atualizado da mensagem de teste" do
    conversation = admin.tenant.whatsapp_conversations.create!(contact_phone: "5547999990000")
    message = conversation.messages.create!(
      tenant: admin.tenant,
      direction: "outbound",
      wa_message_id: "wamid.TEST-STATUS",
      status: "delivered",
      delivered_at: Time.current
    )

    get test_message_status_admin_whatsapp_integration_path(message_id: message.id), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "ok" => true,
      "status" => "delivered",
      "terminal" => true
    )
    expect(response.parsed_body["label"]).to include("Entregue")
  end
end
