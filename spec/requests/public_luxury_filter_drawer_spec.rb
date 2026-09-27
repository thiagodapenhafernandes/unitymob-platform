require "rails_helper"

RSpec.describe "Filtro global no tema luxury", type: :request do
  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Tenant.default.update_columns(public_site_theme: "salute_luxury")
    HomeSetting.instance(tenant: Tenant.default).update!(
      search_filter_display_mode: "floating",
      mobile_search_filter_display_mode: "floating"
    )
  end

  after do
    Tenants::LocalPublicHostOverride.clear!
  end

  it "renderiza o drawer compartilhado na variante luxury, dentro do shell" do
    get root_path

    html = Nokogiri::HTML(response.body)
    shell = html.at_css('[data-controller~="salute-luxury-theme"]')
    wrapper = shell&.at_css('.public-global-search[data-controller="filter-drawer"]')
    drawer = wrapper&.at_css('#public-global-search-drawer.public-theme-filter-drawer--salute-luxury[data-filter-drawer-target="drawer"]')
    form = drawer&.at_css('form[data-filter-drawer-target="form"]')

    expect(response).to have_http_status(:ok)
    expect(drawer).to be_present
    expect(html.css("#public-global-search-drawer").size).to eq(1)
    expect(wrapper.at_css('.public-theme-filter-fab.public-theme-filter-fab--salute-luxury[data-action="click->filter-drawer#open"]')).to be_present
    expect(form["action"]).to eq(habitations_path)
    expect(form.at_css('input[name="transaction_type"]')["value"]).to eq("venda")
    %w[bedrooms suites parking].each do |name|
      pills = form.css(%([data-pill-group="#{name}"] button))
      expect(pills.map(&:text).map(&:strip)).to eq(%w[1 2 3 4+])
      expect(pills.map { |pill| pill["data-name"] }).to eq([name, name, name, "min_#{name}"])
    end
    %w[min_price max_price min_area max_area bedrooms suites parking search].each do |name|
      expect(form.at_css(%(input[name="#{name}"]))).to be_present, "faltou #{name}"
    end
    expect(form.css('.public-theme-combobox input[name="city[]"]').size).to eq(2)
    expect(form.at_css('.public-theme-combobox input[name="category[]"]')).to be_present
    values = form.css('input[name="characteristics[]"]').map { |input| input["value"] }
    expect(values).to include("frente_mar", "quadra_mar", "vista_mar", "mobiliado", "opportunity", "pronto", "cozinha_gourmet_churrasqueira", "varanda")
    expect(values).to eq(values.uniq)
    expect(form.css(".public-theme-filter-drawer__quick-input").map { |input| input["value"] }).to eq(%w[frente_mar quadra_mar vista_mar mobiliado carro_eletrico])
    expect(form.at_css("details")).to be_nil
    expect(form.at_css(".public-theme-filter-drawer__actions .public-theme-filter-drawer__submit[type=submit]")).to be_present
  end

  it "deixa o header sólido fora da home e esconde os filtros próprios da listagem" do
    get habitations_path(transaction_type: "venda")

    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".public-theme-shell")["class"]).to include("sl-shell--solid-header")
    expect(html.at_css(".public-habitations-index__filterbar")["class"]).to include("public-listing-filters--hidden")
    expect(html.at_css(".public-habitations-index__floating-filter")["class"]).to include("public-listing-filters--hidden")
    expect(html.at_css(".public-habitations-index")["class"]).to include("public-header-offset")

    get root_path
    expect(Nokogiri::HTML(response.body).at_css(".public-theme-shell")["class"]).not_to include("sl-shell--solid-header")
  end
end
