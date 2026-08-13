require "rails_helper"

RSpec.describe "Interação do card público de imóvel" do
  let(:card_partial) { Rails.root.join("app/views/shared/tailwind/_property_card.html.erb").read }
  let(:clickable_card_controller) { Rails.root.join("app/javascript/controllers/clickable_card_controller.js").read }

  it "mantém o overlay fora dos eventos do Swiper e preserva o link de tracking" do
    expect(card_partial).to include('class: "absolute inset-0 z-10 pointer-events-none"')
    expect(card_partial).to include("clickable_card_tracking_link: true")
    expect(clickable_card_controller).to include("target.closest('.swiper-button-next')")
    expect(clickable_card_controller).to include("target.closest('.swiper-button-prev')")
    expect(clickable_card_controller).to include("target.closest('.swiper-pagination')")
    expect(clickable_card_controller).to include("trackingLink.click()")
    expect(card_partial).to include("pointerdown->card-swiper#keepInside")
    expect(card_partial).to include("click->card-swiper#keepInside")
    expect(Rails.root.join("app/javascript/controllers/card_swiper_controller.js").read).to include("preventClicksPropagation: true")
  end

  it "mantém variants otimizadas somente nas três primeiras imagens do card" do
    expect(card_partial).to include("property.card_image_sources(3)")
    expect(card_partial).to include("representation_proxy: true, force_variant: true")
    expect(card_partial).to include("public_image_url(pic)")
    expect(card_partial).to include("eager_card_image = priority_image && index.zero?")
    expect(card_partial).to include("visible_card_image = index.zero?")
    expect(card_partial).to include("image_tag(visible_card_image ? image_source : placeholder")
    expect(card_partial).to include("data: (visible_card_image ? {} : { src: image_source })")
  end
end
