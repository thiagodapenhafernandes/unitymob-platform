require "rails_helper"
require_relative "../../support/contract/shared_property_card_examples"

RSpec.describe "public_theme/components/_property_card.html.erb", type: :view do
  before { allow(view).to receive(:current_admin_user).and_return(nil) }
  let(:card_partial) { "public_theme/components/property_card" }
  let(:card_variant) { "salute-luxury" }

  it_behaves_like "contrato do card público"

  it "mantém favorito e compartilhamento no corpo, junto ao preço" do
    render(card_partial, property: create(:habitation), variant: card_variant)
    html = Nokogiri::HTML(rendered)
    expect(html.at_css(".public-theme-property-card__media .public-theme-property-card__favorite")).to be_nil
    expect(html.at_css(".public-theme-property-card__body .public-theme-property-card__price-row .public-theme-property-card__favorite")).to be_present
    expect(html.at_css(".public-theme-property-card__body .broker-share__trigger")).to be_present
    expect(html.at_css("dialog.broker-share__dialog")["aria-label"]).to eq("Compartilhar imóvel")
  end

  it "prioritizes only the visible photo while preserving deferred gallery images" do
    property = create(:habitation)
    allow(property).to receive(:card_image_sources).and_return(["https://example.com/one.jpg", "https://example.com/two.jpg"])
    allow(view).to receive(:public_image_url) { |source, **| source }
    allow(view).to receive(:public_image_srcset).and_return("https://example.com/one.jpg 720w")

    render(card_partial, property: property, variant: card_variant, priority_image: true)
    photos = Nokogiri::HTML(rendered).css(".public-theme-property-card__gallery-frame img")
    expect(photos.first["loading"]).to eq("eager")
    expect(photos.first["fetchpriority"]).to eq("high")
    expect(photos.last["loading"]).to eq("lazy")
    expect(photos.last["data-src"]).to eq("https://example.com/two.jpg")
    expect(photos.last["fetchpriority"]).to be_nil
  end

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

RSpec.describe "shared/tailwind/_property_card.html.erb", type: :view do
  it "serves responsive WebP photos without loading hidden gallery photos upfront" do
    property = create(:habitation)
    allow(property).to receive(:card_image_sources).and_return(["https://example.com/one.jpg", "https://example.com/two.jpg"])
    allow(view).to receive(:public_image_url).with(anything, resize_to_fill: [720, 540], format: :webp) { |source, **| source }
    allow(view).to receive(:public_image_srcset).with(anything, widths: [360, 540, 720], aspect_ratio: 4.0 / 3, crop: true, format: :webp).and_return("https://example.com/small.webp 360w, https://example.com/large.webp 720w")

    view.define_singleton_method(:public_tenant) { property.tenant }
    allow(view).to receive(:current_admin_user).and_return(nil)
    render("shared/tailwind/property_card", property: property, priority_image: true)
    photos = Nokogiri::HTML(rendered).css(".swiper-slide img")
    expect(photos.first["srcset"]).to include("360w", "720w")
    expect(photos.first["fetchpriority"]).to eq("high")
    expect(photos.last["src"]).to start_with("data:image/")
    expect(photos.last["data-src"]).to eq("https://example.com/two.jpg")
    expect(photos.last["srcset"]).to be_nil
  end
end
