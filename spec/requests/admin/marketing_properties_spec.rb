require "rails_helper"

RSpec.describe "Admin::MarketingProperties", type: :request do
  include Devise::Test::IntegrationHelpers

  it "renderiza o estado sem prioridades no workspace de marketing" do
    host! "localhost"
    admin = create(:admin_user, :admin)
    sign_in admin
    insights = instance_double(Seo::MarketingInsights, property_insights: [])
    allow(Seo::MarketingInsights).to receive(:new).with(tenant: admin.tenant).and_return(insights)

    get admin_marketing_properties_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Imóveis com Potencial")
    expect(response.body).to include("Nenhum imóvel priorizado agora")
    expect(response.body).to include("ax-empty-state")
  end
end
