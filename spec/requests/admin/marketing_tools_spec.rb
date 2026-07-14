require "rails_helper"

RSpec.describe "Admin::MarketingTools", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o UTM Builder com componentes compartilhados e preserva os parametros GET" do
    get admin_marketing_tools_path, params: {
      target_url: "/imoveis/frente-mar",
      utm_source: "instagram",
      utm_medium: "social",
      utm_campaign: "frente-mar-maio",
      utm_term: "alto-padrao",
      utm_content: "carrossel"
    }

    doc = Nokogiri::HTML(response.body)
    generated_url = doc.at_css("input#generated_utm_url")

    expect(response).to have_http_status(:ok)
    expect(doc.at_css(".ax-workspace-heading")).to be_present
    expect(doc.css(".ax-operational-panel").size).to eq(2)
    expect(doc.at_css("label[for='target_url']")).to be_present
    expect(doc.at_css("input#utm_campaign")["value"]).to eq("frente-mar-maio")
    expect(generated_url["readonly"]).to eq("readonly")
    expect(generated_url["value"]).to include("utm_source=instagram", "utm_campaign=frente-mar-maio")
  end

  it "nao carrega campanha de outra conta pelo campaign_id" do
    other_tenant = Tenant.create!(name: "Conta externa #{SecureRandom.hex(3)}", slug: "conta-externa-#{SecureRandom.hex(3)}")
    other_campaign = MarketingCampaign.create!(
      tenant: other_tenant,
      name: "Campanha externa",
      channel: "organic",
      status: "idea",
      priority: 2,
      target_url: "/externa",
      utm_campaign: "externa"
    )

    get admin_marketing_tools_path, params: { campaign_id: other_campaign.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Campanha externa", "utm_campaign=externa")
  end
end
