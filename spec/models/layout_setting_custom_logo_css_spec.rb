require "rails_helper"

RSpec.describe LayoutSetting, type: :model do
  describe ".normalized_custom_logo_css" do
    it "mantém apenas regras permitidas para a logo pública" do
      css = <<~CSS
        .custom-logo:before {
          content: "Novo";
          display: block;
        }

        .custom-logo img {
          width: 220px;
          object-fit: contain;
          background-image: url("https://example.com/tracker.png");
        }

        body {
          display: none;
        }
      CSS

      normalized = described_class.normalized_custom_logo_css(css)

      expect(normalized).to include('.custom-logo::before { content: "Novo"; display: block; }')
      expect(normalized).to include(".custom-logo img { width: 220px; object-fit: contain; }")
      expect(normalized).not_to include("body", "url(")
    end

    it "permite recortar a logo e configurar pseudo-elementos com content vazio" do
      css = <<~CSS
        .custom-logo { height: 36px; overflow: hidden; display: flex; align-items: baseline; }
        .custom-logo::before { content: ""; display: block; }
        .custom-logo::after { content: ""; display: block; }
        .custom-logo img { width: 170px; object-fit: contain; }
      CSS

      normalized = described_class.normalized_custom_logo_css(css)

      expect(normalized).to include(".custom-logo { height: 36px; overflow: hidden; display: flex; align-items: baseline; }")
      expect(normalized).to include('.custom-logo::before { content: ""; display: block; }')
      expect(normalized).to include('.custom-logo::after { content: ""; display: block; }')
      expect(normalized).to include(".custom-logo img { width: 170px; object-fit: contain; }")
    end

    it "permite assinatura textual posicionada no pseudo-elemento" do
      css = <<~CSS
        .custom-logo::before {
          content: "Toninho Roncaglio";
          display: block;
          color: #988257;
          position: absolute;
          bottom: -18px;
          right: 15px;
          font-size: 13px;
          font-family: unset;
          font-style: italic;
        }
      CSS

      normalized = described_class.normalized_custom_logo_css(css)

      expect(normalized).to include(
        '.custom-logo::before { content: "Toninho Roncaglio"; display: block; color: #988257; position: absolute; bottom: -18px; right: 15px; font-size: 13px; font-family: unset; font-style: italic; }'
      )
    end

    it "permite regras da logo dentro de media query por largura" do
      css = <<~CSS
        @media (min-width: 1080px) {
          .custom-logo { height: 36px; overflow: hidden; }
          .custom-logo::before { content: "Desktop"; display: block; }
          body { display: none; }
        }

        @media (max-width: 767px) {
          .custom-logo img { width: 140px; object-fit: contain; }
        }
      CSS

      normalized = described_class.normalized_custom_logo_css(css)

      expect(normalized).to include("@media (min-width: 1080px) {\n  .custom-logo { height: 36px; overflow: hidden; }\n  .custom-logo::before { content: \"Desktop\"; display: block; }\n}")
      expect(normalized).to include("@media (max-width: 767px) {\n  .custom-logo img { width: 140px; object-fit: contain; }\n}")
      expect(normalized).not_to include("body")
    end

    it "mantém ajuste isolado de pseudo-elemento dentro de media query mobile" do
      css = <<~CSS
        @media (max-width: 767px) {
          .custom-logo::after {
             top: 2px;
          }
        }
      CSS

      normalized = described_class.normalized_custom_logo_css(css)

      expect(normalized).to eq("@media (max-width: 767px) {\n  .custom-logo::after { top: 2px; }\n}")
    end

    it "ignora media queries fora do formato permitido" do
      css = <<~CSS
        @media print {
          .custom-logo { display: none; }
        }

        @media (min-width: 3600px) {
          .custom-logo { display: none; }
        }
      CSS

      normalized = described_class.normalized_custom_logo_css(css)

      expect(normalized).to be_blank
    end
  end
end
