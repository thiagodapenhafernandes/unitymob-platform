require "rails_helper"

RSpec.describe "Seções da home", type: :request do
  let(:tenant) { Tenant.default }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def html = Nokogiri::HTML(response.body)

  def section_codes(section)
    html.css("[data-public-home-section='#{section.id}'] [data-property-id]").map { _1["data-property-id"] }.uniq
  end

  it "não repete o mesmo imóvel em seções automáticas seguidas e usa o cabeçalho do contrato" do
    create_list(:habitation, 4, tenant:, exibir_no_site_flag: true)
    first = tenant.home_sections.create!(section_type: :featured_properties, title: "Destaques", active: true, order_position: 1, property_filters: { "exibir_no_site" => "1" })
    second = tenant.home_sections.create!(section_type: :opportunities, title: "Mais imóveis", active: true, order_position: 2, property_filters: { "exibir_no_site" => "1" })
    allow_any_instance_of(HomeSections::Showcase).to receive(:limit).and_return(2)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(section_codes(first)).to be_present
    expect(section_codes(first) & section_codes(second)).to be_empty
    head = html.at_css("[data-public-home-section='#{first.id}'] .public-theme-section__head--default .public-theme-section__title")
    expect(head.text.strip).to eq("Destaques")
    expect(html.at_css("[data-public-home-section='#{first.id}'] a.public-theme-section__cta--default")).to be_present
    expect(html.at_css("[data-public-home-section='#{second.id}']")["class"]).to include("public-theme-home-section--alt")
  end

  it "mostra a seção Explore por cidade com links que filtram de verdade" do
    create(:habitation, tenant:, exibir_no_site_flag: true,
                        address_attributes: { logradouro: "Rua 1", numero: "1", bairro: "Centro", cidade: "Itajaí", uf: "SC" })
    section = tenant.home_sections.create!(section_type: :city_links, title: "Explore por cidade", active: true, order_position: 1)

    get root_path

    block = html.at_css("[data-public-home-section='#{section.id}']")
    expect(block.at_css(".public-theme-section__title").text.strip).to eq("Explore por cidade")
    expect(block.at_css(".public-theme-city-links--home .public-theme-city-links__city-name").text).to include("Itajaí")
    expect(block.at_css(".public-theme-city-links__title")).to be_nil
    expect(block.css("a").map { _1["href"] }).to include(empreendimentos_path(cidade: "Itajaí"))
  end

  it "usa o WhatsApp real da conta na chamada para contato e omite o botão sem número" do
    section = tenant.home_sections.create!(section_type: :cta_contact, title: "Vamos conversar?", active: true, order_position: 1)
    ContactSetting.instance(tenant:).update!(whatsapp_primary: "(47) 99123-4567")

    get root_path
    links = html.css("[data-public-home-section='#{section.id}'] a").map { _1["href"] }
    expect(links).to include("https://wa.me/5547991234567")
    expect(response.body).not_to include("5547999999999")

    ContactSetting.instance(tenant:).update!(whatsapp_primary: nil)
    Rails.cache.clear
    get root_path
    expect(html.css("[data-public-home-section='#{section.id}'] a[href^='https://wa.me']")).to be_empty
  end

  it "o hero luxury lista cidades e bairros com rótulo e valor" do
    tenant.update_columns(public_site_theme: "salute_luxury")
    create(:habitation, tenant:, exibir_no_site_flag: true,
                        address_attributes: { logradouro: "Rua 1", numero: "1", bairro: "Centro", cidade: "Itajaí", uf: "SC" })

    get root_path

    options = html.css(".public-theme-hero__search [aria-labelledby='sl-lbl-loc'] ~ .public-theme-combobox__panel .public-theme-combobox__option")
    expect(options.map { _1["data-value"] }).to include("Itajaí", "Centro - Itajaí")
    expect(options.map(&:text).join).not_to include("{")
  end
end
