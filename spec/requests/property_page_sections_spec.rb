require "rails_helper"

RSpec.describe "Página do imóvel — seções no formato completo", type: :request do
  before { host! "localhost" }

  def address(bairro: "Centro")
    { logradouro: "Rua das Flores", numero: "10", bairro: bairro, cidade: "Balneário Camboriú", uf: "SC" }
  end

  it "organiza breadcrumb, listas, empreendimento discreto, bairro e cidades" do
    development = create(:habitation, codigo: "DEV-SECOES", tipo: "Empreendimento", categoria: "Apartamento", nome_empreendimento: "Residencial Secreto",
                                      infra_estrutura: ["Piscina", "Academia"], address_attributes: address)
    unit = create(:habitation, codigo: "UNI-SECOES", slug: "unidade-secoes", categoria: "Apartamento",
                               codigo_empreendimento: development.codigo, nome_empreendimento: "Residencial Secreto",
                               caracteristicas: ["Sacada", "Churrasqueira"], infra_estrutura: ["Piscina"],
                               address_attributes: address)
    neighbor = create(:habitation, codigo: "VIZINHO-1", slug: "vizinho-1", dormitorios_qtd: 9, address_attributes: address)

    get habitation_path(unit)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)

    crumbs = html.css(".public-habitations-show__breadcrumb--desktop a, .public-habitations-show__breadcrumb--desktop span[aria-current]").map { _1.text.strip }
    expect(crumbs).to eq(["Início", "Imóveis", "Balneário Camboriú", "Centro", "Apartamento", "UNI-SECOES"])
    expect(html.at_css('.public-habitations-show__breadcrumb--desktop a[href*="city"][href*="Centro"]')).to be_present

    expect(html.css(".public-habitations-show__media-action").map { _1.text.squish }).to include("Condições de pagamento")

    groups = html.css(".public-theme-property-amenities__group")
    expect(groups.map { _1.at_css(".public-theme-property-amenities__title").text }).to eq(
      ["O que você vai encontrar nesse imóvel", "O que você vai encontrar nesse empreendimento"]
    )
    expect(groups.last.css(".public-theme-property-amenities__item").map { _1.text.strip }).to include("Piscina", "Academia")

    block = html.at_css(".public-theme-property-development--default")
    expect(block).to be_present
    expect(block.text).to include("Conheça o empreendimento deste imóvel")
    expect(response.body).not_to include("Residencial Secreto")
    expect(block.at_css(".public-theme-property-development__link")).to be_nil

    neighborhood = html.at_css(".public-habitations-show__related--neighborhood")
    expect(neighborhood.text).to include("Mais imóveis em Centro")
    expect(neighborhood.text).to include(neighbor.display_title)

    expect(html.at_css(".public-theme-city-links--default .public-theme-city-links__city-name").text).to include("Balneário Camboriú")
    expect(html.at_css('.public-theme-city-links a[href*="transaction_type=aluguel"]')).to be_present

    breadcrumb_json = response.body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
      .map { JSON.parse(_1) rescue nil }.compact.find { _1["@type"] == "BreadcrumbList" }
    expect(breadcrumb_json["itemListElement"].map { _1["name"] }).to include("Balneário Camboriú", "Centro")
  end

  it "loads linked development image variants in bulk while keeping its photos" do
    development = create(:habitation, tipo: "Empreendimento", codigo: "DEV-PRELOAD", address_attributes: address)
    4.times do |index|
      development.photos.attach(io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "photo-#{index}.png", content_type: "image/png")
    end
    unit = create(:habitation, codigo_empreendimento: development.codigo, address_attributes: address)
    variant_lookups = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      variant_lookups << sql if sql.include?("active_storage_variant_records") && sql.include?("variation_digest") && sql.start_with?("SELECT")
    end
    begin
      get habitation_path(unit)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css(".public-theme-property-development__photo").size).to eq(4)
    expect(variant_lookups).to be_empty
  end

  describe "identidade do empreendimento por conta" do
    def create_unit_with_development(name:)
      development = create(:habitation, codigo: "DEV-ID-#{SecureRandom.hex(3)}", tipo: "Empreendimento", categoria: "Apartamento",
                                        nome_empreendimento: name, infra_estrutura: ["Piscina"], address_attributes: address)
      create(:habitation, slug: "unidade-id-#{SecureRandom.hex(3)}", categoria: "Apartamento", codigo_empreendimento: development.codigo,
                          nome_empreendimento: name, address_attributes: address)
    end

    it "revela nome e link quando a conta liga a opção" do
      PublicSiteProfile.new({ show_development_identity: "1" }, tenant: Tenant.default).save
      unit = create_unit_with_development(name: "Residencial Aberto")

      get habitation_path(unit)

      block = Nokogiri::HTML(response.body).at_css(".public-theme-property-development")
      expect(block.at_css(".public-theme-property-development__title").text).to eq("Residencial Aberto")
      expect(block.text).to include("Rua das Flores")
    end

    it "fica discreto quando a opção está ligada mas o empreendimento não tem nome" do
      PublicSiteProfile.new({ show_development_identity: "1" }, tenant: Tenant.default).save
      unit = create_unit_with_development(name: "")

      get habitation_path(unit)

      block = Nokogiri::HTML(response.body).at_css(".public-theme-property-development")
      expect(block.at_css(".public-theme-property-development__title").text).to eq("Conheça o empreendimento deste imóvel")
      expect(block.at_css(".public-theme-property-development__link")).to be_nil
      expect(block.text).not_to include("Rua das Flores")
    end
  end

  describe "/links-uteis" do
    it "volta para a home quando não há links e mostra a lista quando há" do
      get links_uteis_path
      expect(response).to redirect_to(root_path)

      PublicSiteProfile.new({ useful_links: "Prefeitura|https://prefeitura.exemplo.gov.br|Portal|bank" }, tenant: Tenant.default).save
      get links_uteis_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Prefeitura")
    end
  end

  it "não mostra o card \"Informações\" vazio na lateral" do
    plain = create(:habitation, slug: "sem-informacoes", data_entrega: nil, address_attributes: address)
    allow_any_instance_of(Habitation).to receive(:unique_features).and_return([])

    get habitation_path(plain)

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(".public-habitations-show__info-card")).to be_nil
  end
end

