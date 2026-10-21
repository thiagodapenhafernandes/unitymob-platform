require "rails_helper"

RSpec.describe "Busca pública por diária", type: :request do
  let(:tenant) { Tenant.default }
  let(:setting) { HomeSetting.instance(tenant:) }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def html = Nokogiri::HTML(response.body)

  Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
    %w[classic bar card].each do |layout|
      it "controla Diária no tema #{theme}, layout #{layout}, na home e no filtro detalhado" do
        tenant.update!(public_site_theme: theme)
        setting.update!(hero_layout: layout, search_filter_display_mode: "both")
        get root_path
        expect(response).to have_http_status(:ok)
        expect(html.css('button[data-value="diaria"], button[data-transaction-type="diaria"]')).to be_empty

        setting.update!(daily_rental_search_enabled: true)
        get root_path
        expect(response).to have_http_status(:ok)
        expect(html.at_css('.public-theme-filter-drawer button[data-value="diaria"]')&.text).to eq("Diária")
        expect(html.css('button[data-value="diaria"], button[data-transaction-type="diaria"]').size).to eq(2)

        get habitations_path(transaction_type: "diaria")
        expect(response).to have_http_status(:ok)
        expect(html.at_css('.public-theme-filter-drawer button[data-value="diaria"]')['aria-pressed']).to eq("true")
        track = html.at_css('.public-theme-filter-drawer__range-track[data-range="valor"]')
        expect(track['data-min']).to eq("0")
        expect(track['data-step']).to eq("50")
      end
    end
  end

  it "mantém a chave desativada por padrão e isolada por conta" do
    other = Tenant.create!(name: "Outra conta", slug: "daily-#{SecureRandom.hex(4)}")
    expect(setting.daily_rental_search_enabled?).to be(false)
    setting.update!(daily_rental_search_enabled: true)
    expect(HomeSetting.instance(tenant: other).daily_rental_search_enabled?).to be(false)
    setting.update!(daily_rental_search_enabled: false)
    get root_path
    expect(html.css('button[data-value="diaria"], button[data-transaction-type="diaria"]')).to be_empty
  end

  it "preserva a finalidade e o preço na URL canônica e filtra só diárias públicas da conta" do
    setting.update!(daily_rental_search_enabled: true)
    daily = create(:habitation, tenant:, status: "Diária", codigo: "DAILY-300", valor_venda_cents: 0, valor_locacao_cents: 30_000)
    intake = create(:habitation, tenant:, status: "Aluguel", intake_modalidade: "locacao_diaria", codigo: "DAILY-400", valor_venda_cents: 0, valor_locacao_cents: 40_000)
    monthly = create(:habitation, tenant:, status: "Aluguel", codigo: "MONTHLY-300", valor_venda_cents: 0, valor_locacao_cents: 30_000)
    create(:habitation, tenant:, status: "Diária", codigo: "DAILY-PRIVATE", exibir_no_site_flag: false, valor_locacao_cents: 30_000)
    other = Tenant.create!(name: "Outra conta", slug: "daily-other-#{SecureRandom.hex(4)}")
    create(:habitation, tenant: other, status: "Diária", codigo: "DAILY-OTHER", valor_locacao_cents: 30_000)

    get habitations_path(transaction_type: "diaria", min_price: 250, max_price: 450, sort: "price_asc", v: 2)
    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to include("/imoveis/diaria/")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(daily.codigo, intake.codigo)
    expect(response.body).not_to include(monthly.codigo, "DAILY-PRIVATE", "DAILY-OTHER")

    get "/imoveis/diaria"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(daily.codigo)
    expect(response.body).not_to include(monthly.codigo)

    get habitations_path(transaction_type: "diaria", price_range: "1000-0", v: 2)
    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to include("/imoveis/diaria/a-partir-de-1-mil")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(daily.codigo, intake.codigo)
  end
end
