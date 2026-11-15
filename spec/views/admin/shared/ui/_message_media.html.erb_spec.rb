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
  it "tenta imagem ou vídeo para stories sem tipo e mantém tratamento de indisponibilidade" do
    render partial: "admin/shared/ui/message_media", locals: { kind: "auto", url: "https://example.com/story", inline: true }
    doc = Nokogiri::HTML.fragment(rendered)
    expect(doc.at_css('[data-message-media-auto-value="true"]')).to be_present
    expect(doc.at_css('img[data-action="error->message-media#failed"]')).to be_present
    expect(doc.at_css('.ax-message-preview__media-container--inline')).to be_present
    expect(doc.at_css('video[autoplay], audio[autoplay]')).to be_nil
  end

  it "abre arquivos de outros formatos sem executá-los dentro da conversa" do
    render partial: "admin/shared/ui/message_media", locals: { kind: "document", url: "https://example.com/file.pdf" }
    doc = Nokogiri::HTML.fragment(rendered)
    expect(doc.at_css('a[target="_blank"]')["rel"]).to include("noreferrer")
    expect(doc.at_css('iframe, object, embed')).to be_nil
  end

end
