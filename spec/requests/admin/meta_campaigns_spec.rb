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
    expect(response.body).to include("CTR", "CPC", "CPM", "R$ 100,00", "5,0%")
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
    expect(response.body).to include("ax-workspace-heading--plain", "bootstrap-brands/meta", "ax-filter-form")
    expect(Nokogiri::HTML(response.body).css(".ax-studio-nav a").size).to eq(2)
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
  it "mantém o funil do CRM visível sem investimento sincronizado" do
    create(:lead, tenant: tenant, admin_user: admin, other_information: {"meta_campaign_id" => "sem-insight", "meta_campaign_name" => "Campanha sem sincronização"})
    get admin_meta_campaigns_path
    expect(response.body).to include("Campanha sem sincronização", "Configurar contas de anúncios", "Como resolver")
    row = Nokogiri::HTML(response.body).at_css(".ax-table tbody tr")
    expect(row.css("td")[1].text.strip).to eq("—")
  end

  it "preserva conta e filtros ao solicitar sincronização" do
    expect { post sync_now_admin_meta_campaigns_path(tab: "spend", period: 7, account: "456") }
      .to have_enqueued_job(MetaInsightsSyncJob).with(tenant.id)
    expect(response).to redirect_to(admin_meta_campaigns_path(tab: "spend", period: "7", account: "456"))
  end

  it "não mistura dados de outro tenant nos indicadores" do
    other_tenant = Tenant.create!(name: "Outro marketing", slug: "outro-marketing-#{SecureRandom.hex(3)}")
    MetaCampaignInsight.create!(tenant: other_tenant, campaign_id: "outro", campaign_name: "Campanha privada", date: Date.current, spend: 999)
    get admin_meta_campaigns_path(tab: "spend")
    expect(response.body).not_to include("Campanha privada", "R$ 999,00")
  end
  it "pagina as duas tabelas em lotes de 10 preservando filtros e totais" do
    12.times do |i|
      MetaCampaignInsight.create!(tenant: tenant, ad_account_id: "123", campaign_id: "page#{i}", campaign_name: "Campanha #{i}", date: Date.current, spend: 100, leads: 1)
      create(:lead, tenant: tenant, admin_user: admin, other_information: {"meta_campaign_id" => "page#{i}"})
    end
    %w[funnel spend].each do |tab|
      get admin_meta_campaigns_path(tab: tab, period: 7, account: "123")
      html = Nokogiri::HTML(response.body)
      expect(html.css(".ax-table tbody tr").size).to eq(10)
      expect(html.at_css('.ax-pagination a[rel="next"]')["href"]).to include("page=2", "period=7", "account=123", "tab=#{tab}")
      expect(response.body).to include("R$ 1.200,00")
      get admin_meta_campaigns_path(tab: tab, period: 7, account: "123", page: 2)
      expect(Nokogiri::HTML(response.body).css(".ax-table tbody tr").size).to eq(2)
      expect(response.body).to include("R$ 1.200,00")
    end
  end

end
