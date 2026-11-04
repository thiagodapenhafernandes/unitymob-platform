require "rails_helper"

RSpec.describe "Formulários operacionais", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "preserva a modalidade diária ao iniciar a captação" do
    post admin_captacoes_path, params: { habitation: { cadastro_type: "residenciais", categoria: "Apartamento", modalidade: "locacao_diaria" } }
    property = admin.tenant.habitations.broker_intakes.order(:created_at).last
    expect(response).to have_http_status(:redirect)
    expect(property).to have_attributes(status: "Diária", intake_modalidade: "locacao_diaria")
  end

  it "renderiza o status comercial e um único modal de saída no cadastro do imóvel" do
    property = create(:habitation, tenant: admin.tenant)
    get edit_admin_habitation_path(property)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css('select[name="habitation[status]"]').size).to eq(1)
    expect(html.css('#habitationFormUnsavedChanges').size).to eq(1)
    expect(html.at_css('#admin_habitation_form #habitationFormUnsavedChanges')).to be_present
    expect(html.at_css('[data-action="save-state#discardAndNavigate"]').text).to eq("Sair sem salvar")
  end

  it "permite configurar título Corporate por conta e renderiza seu campo no admin" do
    setting = HomeSetting.instance(tenant: admin.tenant)
    patch admin_home_setting_path, params: { home_setting: { corporate_title: "Salute Corporate" } }
    expect(setting.reload.corporate_title).to eq("Salute Corporate")
    get edit_admin_home_setting_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="home_setting[corporate_title]"')
  end

  it "salva isolamento por conta e a participação de cada número no atendimento" do
    integration = WhatsappBusinessIntegration.current(admin.tenant)
    integration.save!
    patch admin_whatsapp_integration_path, params: { whatsapp_business_integration: { separate_conversations_by_number: "1" } }
    expect(integration.reload.separate_conversations_by_number).to be(true)
    number = create(:whatsapp_sender_number, tenant: admin.tenant, whatsapp_business_integration: integration)
    patch admin_whatsapp_sender_number_path(number), params: { whatsapp_sender_number: { administrative_inbox_enabled: "0" } }
    expect(number.reload.administrative_inbox_enabled).to be(false)
  end
end
