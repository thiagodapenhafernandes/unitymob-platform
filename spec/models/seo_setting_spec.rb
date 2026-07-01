require "rails_helper"

RSpec.describe SeoSetting, type: :model do
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
