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
  end

  it "mantém variants otimizadas somente nas seis primeiras imagens do card" do
    expect(card_partial).to include("property.card_image_sources(6)")
    expect(card_partial).to include("if index < 6")
    expect(card_partial).to include("public_image_url(pic, resize_to_fill: [640, 480], format: :webp)")
    expect(card_partial).to include("public_image_url(pic)")
    expect(card_partial).to include("image_tag(index.zero? ? image_source : placeholder")
    expect(card_partial).to include("data: (index.zero? ? {} : { src: image_source })")
  end
end
