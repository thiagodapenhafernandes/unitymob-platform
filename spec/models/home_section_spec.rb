require "rails_helper"

RSpec.describe HomeSection, type: :model do
  describe "property filters" do
    it "normaliza o filtro legado de exibir_site_salute para exibir_no_site" do
      section = described_class.new(
        section_type: "featured_properties",
        title: "Destaques",
        property_filters: { "exibir_site_salute" => "1" }
      )

      section.valid?

      expect(section.property_filters).to eq("exibir_no_site" => "1")
      expect(section.property_filter_enabled?("exibir_no_site")).to be(true)
      expect(section.property_filter_labels).to include("Exibir no site")
    end

    it "filtra imóveis pela flag genérica de publicação no site" do
      section = described_class.new(
        section_type: "featured_properties",
        title: "Destaques",
        property_filters: { "exibir_no_site" => "1" }
      )
      published = create(:habitation, exibir_no_site_flag: true)
      hidden = create(:habitation, exibir_no_site_flag: false)

      expect(section.apply_property_filters(Habitation.all)).to include(published)
      expect(section.apply_property_filters(Habitation.all)).not_to include(hidden)
    end

    it "preserva IDs selecionados manualmente de forma normalizada" do
      section = described_class.new(
        section_type: "featured_properties",
        title: "Destaques",
        property_filters: { "selected_property_ids" => ["", "12", "12", "abc", "34"] }
      )

      section.valid?

      expect(section.selected_property_ids).to eq([12, 34])
      expect(section.property_filters).to eq("selected_property_ids" => [12, 34])
      expect(section.property_filter_labels).to include("2 imóveis selecionados")
    end

    it "aplica filtros comerciais adicionais sem mudar o escopo recebido" do
      section = described_class.new(
        section_type: "opportunities",
        title: "Oportunidades",
        property_filters: { "frente_mar" => "1", "preco_reduzido" => "1" }
      )
      matching = create(:habitation, frente_mar_avenida_atlantica_flag: true, valor_venda_cents: 900_000_00, valor_venda_anterior_cents: 1_000_000_00)
      without_discount = create(:habitation, frente_mar_avenida_atlantica_flag: true, valor_venda_cents: 900_000_00, valor_venda_anterior_cents: 900_000_00)
      without_location = create(:habitation, frente_mar_avenida_atlantica_flag: false, valor_venda_cents: 900_000_00, valor_venda_anterior_cents: 1_000_000_00)

      filtered = section.apply_property_filters(Habitation.all)

      expect(filtered).to include(matching)
      expect(filtered).not_to include(without_discount, without_location)
    end

    it "aplica filtros de transação como curadoria operacional" do
      section = described_class.new(
        section_type: "featured_properties",
        title: "Locação",
        property_filters: { "locacao" => "1" }
      )
      rental = create(:habitation, valor_locacao_cents: 4_500_00, valor_venda_cents: 0)
      sale = create(:habitation, valor_locacao_cents: 0, valor_venda_cents: 950_000_00)

      filtered = section.apply_property_filters(Habitation.all)

      expect(filtered).to include(rental)
      expect(filtered).not_to include(sale)
      expect(section.property_filter_labels).to include("Locação")
    end

    it "infere o tipo tecnico a partir dos filtros selecionados" do
      expect(described_class.infer_section_type_from_filters({ "empreendimentos" => "1" })).to eq("developments")
      expect(described_class.infer_section_type_from_filters({ "locacao" => "1" })).to eq("rentals")
      expect(described_class.infer_section_type_from_filters({ "preco_reduzido" => "1" })).to eq("opportunities")
      expect(described_class.infer_section_type_from_filters({})).to eq("featured_properties")
    end
  end
end
