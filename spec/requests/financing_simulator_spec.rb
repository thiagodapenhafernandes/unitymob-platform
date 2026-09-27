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
    expect(html.at_css(".public-theme-financing-simulator, .public-theme-financing-trigger, #simulador-financiamento-modal")).to be_nil
    expect(html.css("a").map { _1["href"] }).not_to include(simulador_path)
  end

  it "no imóvel à venda: botão no card de preço com parcela de chamada e simulador em modal" do
    sale = create(:habitation, tenant:, exibir_no_site_flag: true, status: "Venda", valor_venda_cents: 850_000_00)

    get habitation_path(sale)

    # Bloco próprio logo abaixo do card "Valor de venda", não dentro dele.
    expect(html.at_css(".public-habitations-show__price-card .public-theme-financing-trigger")).to be_nil
    trigger = html.at_css(".public-habitations-show__desktop-price .public-theme-financing-card--default .public-theme-financing-trigger--default")
    expect(trigger["data-action"]).to eq("financing-modal-trigger#open")
    # 850 mil, 20% de entrada, 30 anos, 11,3% a.a., Price: R$ 6.349,62.
    expect(trigger.at_css(".public-theme-financing-trigger__teaser").text).to include("R$ 6.350")

    modal = html.at_css("dialog#simulador-financiamento-modal[data-controller='financing-modal']")
    expect(modal["data-action"]).to include("public-financing:open@window->financing-modal#open", "cancel->financing-modal#cancel")
    simulator = modal.at_css("#simulador-financiamento.public-theme-financing-simulator--property")
    expect(simulator.at_css("#simulador-valor")["value"]).to eq("850.000")
    expect(simulator.at_css(".public-theme-financing-simulator__cta")["data-property-id"]).to eq(sale.id.to_s)
    expect(simulator["data-financing-simulator-property-label-value"]).to include(sale.codigo)
    expect(html.css(".public-habitations-show__media-action[data-controller='financing-modal-trigger']")).to be_present
    # Termos em português para o visitante.
    expect(simulator.css(".public-theme-financing-simulator__system-name").map { _1.text.squish })
      .to eq(["Parcelas decrescentes Sistema de amortização constante (SAC)", "Parcelas fixas Sistema francês de amortização"])
    expect(simulator.text).not_to match(/\bPrice\b/)
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

  it "imóvel acima do teto do SFH (R$ 1,5 mi) usa a média de taxas de mercado" do
    sale = create(:habitation, tenant:, exibir_no_site_flag: true, status: "Venda", valor_venda_cents: 9_590_000_00)

    get habitation_path(sale)

    simulator = html.at_css("#simulador-financiamento")
    expect(simulator.at_css("#simulador-taxa")["value"]).to eq("14.28")
    expect(simulator.at_css(".public-theme-financing-simulator__hint").text).to include("14,28% a.a.", "taxas de mercado (Banco Central jul/2026). Imóveis acima de R$ 1,5 mi", "fora do SFH")
    expect(simulator["data-financing-simulator-base-rate-value"]).to eq("11.30")
    expect(simulator["data-financing-simulator-market-rate-value"]).to eq("14.28")
    expect(simulator["data-financing-simulator-sfh-limit-value"]).to eq("1500000")
    # 9,59 mi, 20% de entrada, 30 anos a 14,28% a.a., parcelas fixas.
    expect(html.at_css(".public-theme-financing-trigger__teaser").text).to include("R$ 87.409")
    expect(simulator.at_css(".public-theme-financing-simulator__warning")["hidden"]).not_to be_nil
    expect(simulator.at_css(".public-theme-financing-simulator__notice").text).to include("Parcela real um pouco maior")
  end

  it "taxa própria da conta vale também acima do teto do SFH" do
    profile.financing_rate_source = "custom"
    profile.financing_custom_rate = "12"
    expect(profile.save).to be(true)
    sale = create(:habitation, tenant:, exibir_no_site_flag: true, status: "Venda", valor_venda_cents: 3_000_000_00)

    get habitation_path(sale)

    expect(html.at_css("#simulador-taxa")["value"]).to eq("12.00")
    expect(html.at_css("#simulador-financiamento")["data-financing-simulator-market-rate-value"]).to eq("12.00")
  end
end

