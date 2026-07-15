require "rails_helper"

RSpec.describe HabitationsHelper, type: :helper do
  describe "#catalog_property_image_urls" do
    before do
      allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
    end

    it "não inclui fotos de empreendimento quando a unidade não optou pelo fallback" do
      development = create(
        :habitation,
        codigo: "EMP-CATALOG-1",
        tipo: "Empreendimento",
        address_attributes: address_attributes("Empreendimento 1"),
        pictures: [{ "url" => "https://cdn.saluteimoveis.com.br/empreendimento.jpg" }]
      )
      unit = create(
        :habitation,
        codigo: "UNIT-CATALOG-1",
        codigo_empreendimento: development.codigo,
        address_attributes: address_attributes("Unidade 1"),
        pictures: [],
        fotos_empreendimento: [{ "url" => "https://cdn.saluteimoveis.com.br/payload-empreendimento.jpg" }],
        use_development_photos_flag: false
      )

      expect(helper.catalog_property_image_urls(unit)).to be_empty
    end

    it "inclui fotos de empreendimento quando a unidade optou pelo fallback e não tem fotos próprias" do
      development = create(
        :habitation,
        codigo: "EMP-CATALOG-2",
        tipo: "Empreendimento",
        address_attributes: address_attributes("Empreendimento 2"),
        pictures: [{ "url" => "https://cdn.saluteimoveis.com.br/empreendimento.jpg" }]
      )
      unit = create(
        :habitation,
        codigo: "UNIT-CATALOG-2",
        codigo_empreendimento: development.codigo,
        address_attributes: address_attributes("Unidade 2"),
        pictures: [],
        fotos_empreendimento: [{ "url" => "https://cdn.saluteimoveis.com.br/payload-empreendimento.jpg" }],
        use_development_photos_flag: true
      )

      expect(helper.catalog_property_image_urls(unit)).to eq(["https://cdn.saluteimoveis.com.br/empreendimento.jpg"])
    end
  end

  describe "#catalog_property_image_count" do
    before do
      allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
    end

    it "conta todas as fotos públicas mesmo quando a prévia do catálogo é limitada" do
      property = create(
        :habitation,
        codigo: "CATALOG-COUNT-1",
        address_attributes: address_attributes("Imóvel com galeria"),
        pictures: 9.times.map { |index| { "url" => "https://cdn.saluteimoveis.com.br/foto-#{index}.jpg" } }
      )

      expect(helper.catalog_property_image_urls(property).size).to eq(6)
      expect(helper.catalog_property_image_count(property)).to eq(9)
      expect(helper.catalog_property_image_preview_count(property)).to eq(6)
    end

    it "não inclui fotos ocultas na contagem exibida" do
      property = create(
        :habitation,
        codigo: "CATALOG-COUNT-2",
        address_attributes: address_attributes("Imóvel com foto oculta"),
        pictures: [
          { "url" => "https://cdn.saluteimoveis.com.br/visivel.jpg" },
          { "url" => "https://cdn.saluteimoveis.com.br/oculta.jpg", "site_hidden" => true }
        ]
      )

      expect(helper.catalog_property_image_count(property)).to eq(1)
    end
  end

  def address_attributes(logradouro)
    {
      logradouro:,
      bairro: "Centro",
      cidade: "Itapema",
      uf: "SC"
    }
  end
end
