require "rails_helper"

RSpec.describe "Listagem de empreendimentos", type: :request do
  before do
    host! "localhost"
    HomeSetting.instance(tenant: Tenant.default).update!(search_filter_display_mode: "floating", mobile_search_filter_display_mode: "floating")
  end

  def development(name, city:, units:, lancamento: false)
    dev = create(:habitation, tipo: "Empreendimento", nome_empreendimento: name, lancamento_flag: lancamento,
                              address_attributes: { logradouro: "Av. Brasil", numero: "1", bairro: "Centro", cidade: city, uf: "SC" })
    units.times { |i| create(:habitation, codigo_empreendimento: dev.codigo, area_privativa_m2: 90 + i * 10, suites_qtd: 2) }
    dev
  end

  it "ordena por unidades, usa o card compartilhado e tira o filtro global de imóveis" do
    development("Poucas Unidades", city: "Balneário Camboriú", units: 1)
    development("Muitas Unidades", city: "Itajaí", units: 3)

    get empreendimentos_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    titles = html.css(".public-theme-dev-card__title").map { _1.text.strip }
    expect(titles).to eq(["Muitas Unidades", "Poucas Unidades"])
    first_card = html.at_css(".public-theme-developments__grid .public-theme-dev-card")
    expect(first_card.css(".public-theme-dev-card__metric").map { _1.text.split.join(" ") }).to include("90 a 110 m²")
    expect(html.at_css(".public-global-search")).to be_nil
    expect(html.css("#development-names option").map { _1["value"] }).to include("Muitas Unidades", "Poucas Unidades")
    expect(html.at_css(".public-theme-page-head__title").text).to eq("Empreendimentos")
  end

  it "filtra por fase e cidade mantendo os filtros na tela" do
    development("Lançamento BC", city: "Balneário Camboriú", units: 1, lancamento: true)
    development("Pronto Itajaí", city: "Itajaí", units: 1)

    get empreendimentos_path(fase: "lancamento")
    expect(Nokogiri::HTML(response.body).css(".public-theme-dev-card__title").map { _1.text.strip }).to eq(["Lançamento BC"])

    get empreendimentos_path(cidade: "Itajaí")
    html = Nokogiri::HTML(response.body)
    expect(html.css(".public-theme-dev-card__title").map { _1.text.strip }).to eq(["Pronto Itajaí"])
    expect(html.at_css('select[name="cidade"] option[selected]').text).to eq("Itajaí")
    expect(html.at_css(".public-theme-developments__clear")).to be_present
  end

  it "ignora fase e ordem fora da lista" do
    development("Qualquer", city: "Itajaí", units: 1)

    get empreendimentos_path(fase: "destroy_all", ordem: "drop")

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css(".public-theme-dev-card__title").map { _1.text.strip }).to eq(["Qualquer"])
  end

  it "mostra o texto de SEO recolhível depois da grade" do
    development("Com Texto", city: "Itajaí", units: 1)
    Tenant.default.seo_settings.create!(canonical_key: "empreendimentos", page_name: "empreendimentos",
                                        active: true, apply_to_public: true, intro_text: "Curadoria de empreendimentos.")

    get empreendimentos_path

    body = response.body
    expect(body).to include("Curadoria de empreendimentos.")
    expect(body.index("public-theme-developments__about")).to be > body.index("public-theme-developments__grid")
  end
end
