require "rails_helper"

RSpec.describe "admin/shared/ui/_message_media", type: :view do
  before { view.extend Admin::UiHelper }

  %w[image video audio].each do |kind|
    it "renderiza #{kind} com a mídia informada" do
      render partial: "admin/shared/ui/message_media", locals: { kind: kind, url: "https://example.com/media" }
      tag = kind == "image" ? "img" : kind
      expect(Nokogiri::HTML.fragment(rendered).at_css(tag)).to be_present
      expect(rendered).to include("https://example.com/media")
      expect(Nokogiri::HTML.fragment(rendered).at_css("#{tag}[controls]")).to be_present unless kind == "image"
    end
  end

  it "sinaliza quando a mídia não possui endereço disponível" do
    render partial: "admin/shared/ui/message_media", locals: { kind: "image", url: nil }
    expect(rendered).to include("Mídia de exemplo indisponível")
    expect(Nokogiri::HTML.fragment(rendered).at_css("img")).to be_nil
  end
end
