require "rails_helper"
require_relative "../../support/contract/shared_property_card_examples"

RSpec.describe "public_theme/components/_property_card.html.erb", type: :view do
  let(:card_partial) { "public_theme/components/property_card" }
  let(:card_variant) { "salute-luxury" }

  it_behaves_like "contrato do card público"

  it "marca o título para o corte em duas linhas e concorda singular/plural nas medidas" do
    tenant = Tenant.create!(name: "Contrato", slug: "card-contrato-specs")
    single = create(:habitation, tenant: tenant, suites_qtd: 1, vagas_qtd: 1, area_privativa_m2: 55)
    plural = create(:habitation, tenant: tenant, suites_qtd: 3, vagas_qtd: 2, area_privativa_m2: 1250)

    render(card_partial, property: single, variant: card_variant)
    single_html = Nokogiri::HTML(rendered)
    expect(single_html.at_css("h3.public-theme-property-card__title a")["title"]).to eq(single.display_title)
    expect(single_html.css(".public-theme-property-card__spec").map { |spec| spec.text.squish }).to eq(["1 suíte", "1 vaga", "55 m²"])

    render(card_partial, property: plural, variant: card_variant)
    expect(Nokogiri::HTML(rendered).css(".public-theme-property-card__spec").map { |spec| spec.text.squish }.last(3)).to eq(["3 suítes", "2 vagas", "1.250 m²"])
  end
end
