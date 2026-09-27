require "rails_helper"

RSpec.describe "Menu de navegação em tela cheia", type: :request do
  let(:tenant) { Tenant.default }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
    create(:habitation, tenant:, exibir_no_site_flag: true, categoria: "Apartamento", dormitorios_qtd: 2,
                        address_attributes: { logradouro: "Rua 1", numero: "1", bairro: "Centro", cidade: "Itajaí", uf: "SC" })
    create(:store, tenant:, active: true, address: "Av. Brasil", number: "100", neighborhood: "Centro", city: "Itajaí", state: "SC")
    ContactSetting.instance(tenant:).update!(whatsapp_primary: "(47) 99123-4567")
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def overlay
    Nokogiri::HTML(response.body).at_css(".public-theme-navigation-overlay[data-controller='navigation-overlay']")
  end

  it "no tema padrão, o botão do header abre o menu com catálogo, links do admin e contato real" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(overlay["class"]).to include("public-theme-navigation-overlay--default")
    expect(overlay["aria-hidden"]).to eq("true")
    expect(overlay["data-action"]).to include("public-navigation:open@window->navigation-overlay#open", "keydown.esc@window->navigation-overlay#close")

    catalog = overlay.css(".public-theme-navigation-overlay__catalog-group").map { _1.at_css("h2").text.squish }
    expect(catalog.first).to start_with("Todos os imóveis")
    expect(catalog.last).to eq("Navegação")
    apartment = overlay.css(".public-theme-navigation-overlay__catalog-group nav a").find { _1.text.include?("Apartamentos 2 Dormitórios") }
    expect(apartment.at_css("em").text).to eq("1")
    expect(apartment["href"]).to include("bedrooms=2")
    expect(overlay.text).not_to include("Apartamentos 3 Dormitórios")
    city = overlay.css("a").find { _1.text.strip.start_with?("Itajaí") }
    expect(city["href"]).to include("city%5B%5D=Itaja%C3%AD")

    contact = overlay.at_css(".public-theme-navigation-overlay__contact")
    expect(contact.text).to include("Av. Brasil, 100 - Centro · Itajaí - SC")
    expect(contact.at_css("a")["href"]).to eq("https://wa.me/5547991234567")
    # Links internos fecham o menu; o WhatsApp abre em nova aba e o mantém.
    internal = overlay.css("a, button").reject { _1["target"] == "_blank" }
    expect(internal.map { _1["data-action"].to_s }).to all(include("navigation-overlay#close"))
  end

  it "no luxury, usa o mesmo componente com a pele do tema e sem a lista simples antiga" do
    tenant.update_columns(public_site_theme: "salute_luxury")

    get root_path

    shell = Nokogiri::HTML(response.body).at_css('[data-controller~="salute-luxury-theme"]')
    expect(shell.at_css("#saluteLuxuryMenu.sl-mobile-nav.public-theme-navigation-overlay--salute-luxury")).to be_present
    expect(shell.at_css('[data-action*="salute-luxury-theme#openMenu"]')).to be_present
    expect(response.body).not_to include("salute-luxury-theme#closeMenu", "sl-mobile-nav__phone")
  end

  it "sem foto de hero, o menu marca a variante sem mídia" do
    get root_path

    expect(overlay["class"]).to include("public-theme-navigation-overlay--no-media")
    expect(overlay.at_css(".public-theme-navigation-overlay__media")).to be_nil
  end

  it "usa a foto do menu escolhida no admin no lugar da foto do hero" do
    HomeSetting.instance(tenant:).navigation_menu_image.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "menu.png", content_type: "image/png"
    )

    get root_path

    expect(overlay["class"]).not_to include("public-theme-navigation-overlay--no-media")
    expect(overlay.at_css("[data-navigation-overlay-target='media']")["data-src"]).to include("menu.png")
  end
end
