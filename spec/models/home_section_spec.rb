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
  end
end
