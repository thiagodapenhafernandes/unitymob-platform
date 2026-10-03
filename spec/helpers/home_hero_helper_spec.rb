require "rails_helper"

RSpec.describe HomeHeroHelper, type: :helper do
  it "separa os candidatos mobile e desktop e reutiliza as mesmas URLs no hero" do
    assign(:hero_images, [{ source: "desktop", mobile_source: "mobile" }])
    allow(helper).to receive(:public_image_url) do |source, **options|
      "/#{source}/#{options[:resize_to_limit]&.first}.webp"
    end
    sources = helper.hero_image_sources
    expect(sources[:mobile_srcset]).to eq("/mobile/640.webp 640w, /mobile/900.webp 900w")
    expect(sources[:desktop_srcset]).to eq("/desktop/1440.webp 1440w, /desktop/1920.webp 1920w")
    expect(helper.hero_background_locals).to include(
      background_mobile_srcset: sources[:mobile_srcset], background_srcset: sources[:desktop_srcset]
    )
  end
end
