require "rails_helper"

RSpec.describe "Simulador de financiamento", type: :request do
  let(:tenant) { Tenant.default }
  let(:profile) { PublicSiteProfile.current(tenant:) }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def html = Nokogiri::HTML(response.body)

  def disable!
    profile.financing_simulator_enabled = false
    expect(profile.save).to be(true)
  end

  it "fica ligado por padrão: página, item do menu e taxa do Banco Central" do
    get simulador_path

    expect(response).to have_http_status(:ok)
    simulator = html.at_css(".public-theme-financing-simulator--default[data-controller='financing-simulator']")
    expect(simulator).to be_present
    expect(simulator.at_css("#simulador-taxa")["value"]).to eq("11.30")
    expect(simulator.at_css(".public-theme-financing-simulator__hint").text).to include("11,30% a.a.", "Banco Central", "jul/2026")
    expect(simulator.at_css(".public-theme-financing-simulator__cta")["data-action"]).to eq("click->lead-capture#open")
    expect(html.css("a").map { _1["href"] }).to include(simulador_path)
  end

  it "desligado na conta: página some (404), menu sem o item e imóvel sem o bloco" do
    disable!
    sale = create(:habitation, tenant:, exibir_no_site_flag: true, status: "Venda", valor_venda_cents: 800_000_00)

    get simulador_path
    expect(response).to have_http_status(:not_found)

    get habitation_path(sale)
    expect(response).to have_http_status(:ok)
    expect(html.at_css(".public-theme-financing-simulator")).to be_nil
    expect(html.css("a").map { _1["href"] }).not_to include(simulador_path)
  end

  it "na página do imóvel à venda, vem preenchido com o preço e o lead leva o imóvel" do
    sale = create(:habitation, tenant:, exibir_no_site_flag: true, status: "Venda", valor_venda_cents: 850_000_00)

    get habitation_path(sale)

    simulator = html.at_css("#simulador-financiamento.public-theme-financing-simulator--property")
    expect(simulator.at_css("#simulador-valor")["value"]).to eq("850.000")
    expect(simulator.at_css(".public-theme-financing-simulator__cta")["data-property-id"]).to eq(sale.id.to_s)
    expect(simulator["data-financing-simulator-property-label-value"]).to include(sale.codigo)
    expect(html.css("a[href='#simulador-financiamento']")).to be_present
  end

  it "imóvel só para locação não mostra o simulador" do
    rental = create(:habitation, tenant:, exibir_no_site_flag: true, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 3_500_00)

    get habitation_path(rental)

    expect(html.at_css(".public-theme-financing-simulator")).to be_nil
  end

  it "usa a taxa própria da conta quando escolhida" do
    profile.financing_rate_source = "custom"
    profile.financing_custom_rate = "9,75"
    expect(profile.save).to be(true)

    get simulador_path

    expect(html.at_css("#simulador-taxa")["value"]).to eq("9.75")
    expect(html.at_css(".public-theme-financing-simulator__hint").text).to include("9,75% a.a.", "taxa de referência da imobiliária")
  end
end
