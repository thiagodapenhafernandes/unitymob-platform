require "rails_helper"

RSpec.describe PublicThemeIconsHelper, type: :helper do
  it "renderiza Bootstrap Icons aceitando nome puro, com prefixo ou com classe completa" do
    %w[geo-alt bi-geo-alt].push("bi bi-geo-alt").each do |icon|
      node = Nokogiri::HTML.fragment(helper.public_icon(icon, class_name: "extra")).at_css("i")

      expect(node["class"].split).to include("bi", "bi-geo-alt", "public-theme-icon", "public-theme-icon--geo-alt", "extra")
      expect(node["aria-hidden"]).to eq("true")
    end
  end

  it "mapeia nomes legados e cai num ícone neutro quando o nome não existe" do
    expect(helper.public_icon_name("x")).to eq("x-lg")
    expect(helper.public_icon_name("chart")).to eq("graph-up-arrow")
    expect(helper.public_icon_name("nao-existe")).to eq(PublicThemeIconsHelper::PUBLIC_ICON_FALLBACK)
    expect(helper.public_icon_name(nil)).to eq(PublicThemeIconsHelper::PUBLIC_ICON_FALLBACK)
  end

  it "expõe rótulo acessível quando recebe título e repassa data attributes" do
    node = Nokogiri::HTML.fragment(helper.public_icon("heart", title: "Favoritar", data: { public_property_favorite_target: "icon" })).at_css("i")

    expect(node["role"]).to eq("img")
    expect(node["aria-label"]).to eq("Favoritar")
    expect(node["data-public-property-favorite-target"]).to eq("icon")
  end
end
