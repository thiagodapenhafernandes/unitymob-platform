require "rails_helper"

RSpec.describe "shared/tailwind/_development_card.html.erb", type: :view do
  let(:tenant) { Tenant.default }

  before do
    allow(view).to receive(:theme_variant).and_return("salute-luxury")
  end

  it "marca a variante do tema, concorda singular/plural e esconde selo e logo vazios" do
    development = create(:habitation, tenant: tenant, nome_empreendimento: "Residencial Aurora", tipo: "Empreendimento")

    render "shared/tailwind/development_card",
           development: development,
           unit_count: 0,
           unit_metric: { area_label: "94 a 220 m²", suites_label: "1", dorms_label: nil, vagas_label: "1 a 2" }

    html = Nokogiri::HTML(rendered)
    card = html.at_css("article.public-development-card.public-theme-dev-card")

    expect(card["class"]).to include("public-theme-dev-card--salute-luxury")
    expect(card.at_css(".public-theme-dev-card__title").text.strip).to eq("Residencial Aurora")
    expect(card.css(".public-theme-dev-card__metric").map { |metric| metric.text.split.join(" ") }).to eq(["94 a 220 m²", "1 suíte", "1 a 2 vagas"])
    expect(card.at_css(".public-theme-dev-card__count")).to be_nil
    expect(card.at_css(".public-theme-dev-card__logo")).to be_nil
    expect(card.at_css(".public-theme-dev-card__cta")).to be_present
  end

  it "escapa do turbo-frame da seção para abrir a página do empreendimento" do
    development = create(:habitation, tenant: tenant, nome_empreendimento: "Residencial Aurora", tipo: "Empreendimento")

    render "shared/tailwind/development_card", development: development, unit_count: 0, unit_metric: nil

    link = Nokogiri::HTML(rendered).at_css("a.public-development-card-link")
    expect(link["data-turbo-frame"]).to eq("_top")
  end
end
