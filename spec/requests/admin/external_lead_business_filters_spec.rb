require "rails_helper"

RSpec.describe "Filtros de modalidade da integração anterior", type: :request do
  include Devise::Test::IntegrationHelpers

  it "salva entrada e saída independentemente sem alterar outra conta" do
    admin = create(:admin_user, :admin)
    integration = create(:external_lead_integration, tenant: admin.tenant)
    other = create(:external_lead_integration,
      tenant: Tenant.create!(name: "Outra conta", slug: "business-filter-other"))
    host! "localhost"
    sign_in admin

    patch admin_external_lead_integration_path, params: {
      external_lead_integration: { enabled: "1", incoming_business_type: "sale", outgoing_business_type: "sale" }
    }
    expect(response).to redirect_to(admin_external_lead_integration_path)
    expect(integration.reload).to have_attributes(incoming_business_type: "sale", outgoing_business_type: "sale")
    expect(other.reload.outgoing_business_type).to be_nil

    get admin_external_lead_integration_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("select[name='external_lead_integration[outgoing_business_type]'] option[selected]")["value"]).to eq("sale")
  end
end
