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

  describe ".public_inventory" do
    it "remove páginas de seleção e URLs com token de compartilhamento do inventário público" do
      public_page = described_class.create!(
        page_name: "imoveis:inventario-publico",
        canonical_key: "imoveis:inventario-publico",
        page_type: "property_listing",
        canonical_path: "/imoveis",
        active: true,
        apply_to_public: true,
        robots_index: true
      )
      shared_selection = described_class.create!(
        page_name: "ai_property_share_collections_show:inventario",
        canonical_key: "ai_property_share_collections_show:inventario",
        page_type: "ai_property_share_collections_show",
        canonical_path: "/selecoes/token-inventario",
        active: true,
        apply_to_public: true,
        robots_index: true
      )
      shared_property_url = described_class.create!(
        page_name: "imovel-com-token",
        canonical_key: "property:token",
        page_type: "property_show",
        canonical_path: "/imoveis/apartamento?share_token=abc",
        active: true,
        apply_to_public: true,
        robots_index: true
      )

      expect(described_class.public_inventory).to include(public_page)
      expect(described_class.public_inventory).not_to include(shared_selection, shared_property_url)
    end
  end

  describe "#related_habitation" do
    it "consulta o imóvel sem materializar toda a relação do tenant" do
      relation = double("tenant habitations")
      tenant = double("tenant", habitations: relation)
      seo_setting = described_class.new(canonical_key: "property:4114")

      allow(Current).to receive(:tenant).and_return(tenant)
      expect(relation).not_to receive(:blank?)
      expect(relation).to receive(:find_by).with(codigo: "4114").and_return(:habitation)

      expect(seo_setting.send(:related_habitation)).to eq(:habitation)
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
