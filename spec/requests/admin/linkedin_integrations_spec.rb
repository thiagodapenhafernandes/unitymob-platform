require "rails_helper"

RSpec.describe "Admin::LinkedinIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a conexão sem solicitar credenciais técnicas ao cliente" do
    get admin_linkedin_integration_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("LinkedIn", "Lead Sync")
    expect(response.body).not_to include("Client Secret", "Client ID")
  end

  it "salva apenas contas conhecidas desta conexão e preserva o marco de recebimento" do
    integration = create(:linkedin_integration, admin_user: admin)
    original = integration.account_cursors
    patch admin_linkedin_integration_path, params: { linkedin_integration: { selected_account_ids: ["123"] } }
    expect(response).to redirect_to(admin_linkedin_integration_path)
    expect(integration.reload.account_cursors).to eq(original)
    patch admin_linkedin_integration_path, params: { linkedin_integration: { selected_account_ids: ["999"] } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(integration.reload.selected_account_ids).to eq(["123"])
  end

  it "remove a conexão sem excluir os leads ou recibos" do
    integration = create(:linkedin_integration, admin_user: admin)
    lead = create(:lead, tenant: admin.tenant, origin: "LinkedIn Ads", skip_automatic_routing: true)
    receipt = LinkedinLeadReceipt.create!(tenant: admin.tenant, lead: lead, response_id: "keep")
    delete disconnect_admin_linkedin_integration_path
    expect(integration.reload).not_to be_connected
    expect(lead.reload).to be_present
    expect(receipt.reload).to be_present
  end

  it "não expõe as contas de outro tenant" do
    create(:linkedin_integration, ad_accounts: [{ "id" => "999", "name" => "Segredo de outra conta" }], admin_user: create(:admin_user, :admin, tenant: Tenant.create!(name: "Outra", slug: "linkedin-private")))
    get admin_linkedin_integration_path
    expect(response.body).not_to include("Segredo de outra conta")
    post sync_admin_linkedin_integration_path
    expect(response).to have_http_status(:not_found)
  end

  it "bloqueia usuários sem permissão de integrações" do
    sign_out admin
    sign_in create(:admin_user)
    post connect_admin_linkedin_integration_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "rejeita o callback sem state válido sem consultar a API" do
    expect_any_instance_of(Linkedin::Client).not_to receive(:exchange_code)
    get callback_admin_linkedin_integration_path, params: { code: "code", state: "invented" }
    expect(response).to redirect_to(admin_linkedin_integration_path)
    expect(LinkedinIntegration.find_by(tenant: admin.tenant)).to be_nil
  end

  it "valida OAuth, grava token criptografado e impede reutilizar o callback" do
    allow(LinkedinIntegration).to receive(:configured?).and_return(true)
    client = instance_double(Linkedin::Client)
    allow(Linkedin::Client).to receive(:new).and_return(client)
    state = nil
    allow(client).to receive(:authorization_url) do |**args|
      state = args.fetch(:state)
      "https://www.linkedin.com/oauth/v2/authorization?state=#{state}"
    end
    expect(client).to receive(:exchange_code).with("valid-code").once.and_return({ "access_token" => "new-private-token", "expires_in" => 3600 })
    post connect_admin_linkedin_integration_path
    expect(response).to redirect_to("https://www.linkedin.com/oauth/v2/authorization?state=#{state}")
    get callback_admin_linkedin_integration_path, params: { state: state, code: "valid-code" }
    integration = LinkedinIntegration.find_by!(tenant: admin.tenant)
    expect(integration.access_token).to eq("new-private-token")
    expect(integration.access_token_before_type_cast).not_to include("new-private-token")
    expect(integration.admin_user).to eq(admin)
    get callback_admin_linkedin_integration_path, params: { state: state, code: "valid-code" }
    expect(flash[:alert]).to include("validar")
  end

  it "salva os filtros LinkedIn da regra e rejeita formulários externos" do
    create(:linkedin_integration, admin_user: admin)
    post admin_distribution_rules_path, params: { distribution_rule: { name: "Regra LinkedIn", source_linkedin: "1", linkedin_campaign_ids: ["", "456"], linkedin_form_ids: ["", "789"] } }
    rule = admin.tenant.distribution_rules.find_by!(name: "Regra LinkedIn")
    expect(rule).to have_attributes(source_linkedin: true, linkedin_campaign_ids: ["456"], linkedin_form_ids: ["789"])
    patch admin_distribution_rule_path(rule), params: { distribution_rule: { linkedin_form_ids: ["external"] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(rule.reload.linkedin_form_ids).to eq(["789"])
  end

  it "renderiza campanhas e formulários apenas nas regras de distribuição" do
    create(:linkedin_integration, admin_user: admin)
    get admin_linkedin_integration_path
    expect(response.body).to include("Contas de anúncios", "Conta LinkedIn")
    expect(response.body).not_to include("Formulário LinkedIn")
    get new_admin_distribution_rule_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Campanha LinkedIn", "Formulário LinkedIn", "distribution_rule[linkedin_campaign_ids][]")
  end
end
