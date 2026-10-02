require "rails_helper"

RSpec.describe "Admin::MetaCampaigns", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza abas, KPIs e tabelas com join de funil" do
    MetaCampaignInsight.create!(tenant: tenant, ad_account_id: "123", campaign_id: "c1",
                                campaign_name: "Campanha Porto Belo", date: Date.current,
                                spend: 200, impressions: 2000, clicks: 100, leads: 4)
    create(:lead, tenant: tenant, attribution_channel: "meta_ads", admin_user: admin,
                  broker_qualification_status: "qualified",
                  other_information: { "meta_campaign_id" => "c1" })

    get admin_meta_campaigns_path(tab: "funnel", period: 30)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Funil por campanha", "Investimento", "Campanha Porto Belo")
    expect(response.body).to include("R$ 200,00")

    get admin_meta_campaigns_path(tab: "spend", period: 7)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("CTR", "CPC")
  end

  it "filtra por conta de anúncios" do
    MetaCampaignInsight.create!(tenant: tenant, ad_account_id: "123", campaign_id: "c1",
                                campaign_name: "Campanha A", date: Date.current, spend: 100, leads: 2)
    MetaCampaignInsight.create!(tenant: tenant, ad_account_id: "456", campaign_id: "c2",
                                campaign_name: "Campanha B", date: Date.current, spend: 50, leads: 1)

    get admin_meta_campaigns_path(tab: "spend", account: "456")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Campanha B")
    expect(response.body).not_to include("Campanha A")
    expect(response.body).to include("Todas as contas")
  end

  it "exibe cabeçalho com botão Atualizar agora" do
    get admin_meta_campaigns_path(tab: "funnel", period: 30)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading")
    expect(response.body).to include("sync_now")
    expect(response.body.scan("Atualizar agora").size).to be >= 2
  end

  it "mostra estado vazio sem sync e enfileira atualização" do
    get admin_meta_campaigns_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sem dados da Meta ainda")

    expect do
      post sync_now_admin_meta_campaigns_path(tab: "funnel", period: 30)
    end.to have_enqueued_job(MetaInsightsSyncJob).with(tenant.id)
    expect(response).to redirect_to(admin_meta_campaigns_path(tab: "funnel", period: "30"))
  end
end
