require "rails_helper"

RSpec.describe "Admin::WhatsappIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a tela sem duplicar paginas/forms do Meta Leads" do
    get admin_whatsapp_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Integração WhatsApp")
    expect(response.body).to include("WhatsApp Business API")
    expect(response.body).not_to include("Páginas e Formulários")
    expect(response.body).to include("Telefones do Site")
    expect(response.body).to include("1980983762681491")
  end

  it "redireciona a antiga aba de forms para Meta Leads" do
    get admin_whatsapp_integration_path(tab: "forms")

    expect(response).to redirect_to(admin_meta_integrations_path)
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
    service = instance_double(Facebook::WhatsappEmbeddedSignupService, exchange_code!: {
      "access_token" => "business-token",
      "expires_in" => 3600
    })
    allow(Facebook::WhatsappEmbeddedSignupService).to receive(:new).with(code: "code-123").and_return(service)

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
end
