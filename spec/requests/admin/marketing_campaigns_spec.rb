require "rails_helper"

RSpec.describe "Admin::MarketingCampaigns", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o formulário compartilhado sem expor páginas SEO de outro tenant" do
    own_setting = SeoSetting.create!(tenant: admin.tenant, page_name: "SEO da conta", canonical_key: "seo-da-conta")
    other_tenant = Tenant.create!(name: "Outra conta SEO", slug: "outra-seo-#{SecureRandom.hex(4)}")
    other_setting = SeoSetting.create!(tenant: other_tenant, page_name: "SEO de outra conta", canonical_key: "seo-outra-conta")

    get new_admin_marketing_campaign_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("option[value='#{own_setting.id}']")).to be_present
    expect(document.at_css("option[value='#{other_setting.id}']")).not_to be_present
    expect(document.at_css('input[name="marketing_campaign[name]"][required]')).to be_present
    expect(document.at_css('input[name="marketing_campaign[budget]"]')).to be_present
    expect(document.at_css('textarea[name="marketing_campaign[notes]"]')).to be_present
  end

  it "cria a campanha no tenant atual preservando os parâmetros do formulário" do
    expect {
      post admin_marketing_campaigns_path, params: {
        marketing_campaign: {
          name: "Campanha tenant",
          channel: "instagram",
          status: "planned",
          priority: 3,
          target_url: "/imoveis",
          budget: "1.250,50",
          starts_on: Date.current,
          notes: "Campanha criada pelo formulário compartilhado"
        }
      }
    }.to change { admin.tenant.marketing_campaigns.count }.by(1)

    expect(response).to redirect_to(admin_marketing_campaigns_path)
    campaign = admin.tenant.marketing_campaigns.order(:id).last
    expect(campaign).to have_attributes(name: "Campanha tenant", channel: "instagram", status: "planned", priority: 3)
    expect(campaign.budget_cents).to eq(125_050)
  end
end
