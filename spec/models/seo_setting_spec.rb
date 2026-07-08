require "rails_helper"

RSpec.describe SeoSetting, type: :model do
  describe "#social_image_url" do
    it "prioriza a imagem específica da página sobre a imagem global" do
      seo_setting = described_class.new(og_image: "/icon.png")

      expect(
        seo_setting.social_image_url(
          base_url: "https://saluteimoveis.com.br",
          page_image: "https://cdn.saluteimoveis.com.br/imoveis/foto.jpg"
        )
      ).to eq("https://cdn.saluteimoveis.com.br/imoveis/foto.jpg")
    end
  end

  describe ".page_type_label_for" do
    it "traduz tipos técnicos de página para pt-BR" do
      expect(described_class.page_type_label_for("property_show")).to eq("Imóvel")
      expect(described_class.page_type_label_for("property_listing")).to eq("Busca de imóveis")
      expect(described_class.page_type_label_for("development_show")).to eq("Empreendimento")
      expect(described_class.page_type_label_for("landing_pages_show")).to eq("Landing page")
      expect(described_class.page_type_label_for("developments_index")).to eq("Busca de empreendimentos")
      expect(described_class.page_type_label_for("development_landing")).to eq("Landing de empreendimento")
      expect(described_class.page_type_label_for("property_landing")).to eq("Landing de imóveis")
      expect(described_class.page_type_label_for("legacy")).to eq("Legado")
    end

    it "mantém tipos desconhecidos legíveis" do
      expect(described_class.page_type_label_for("custom_page_type")).to eq("Custom page type")
      expect(described_class.page_type_label_for(nil)).to eq("Sem tipo")
    end
  end
end
