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

  def address_attributes(logradouro)
    {
      logradouro:,
      bairro: "Centro",
      cidade: "Itapema",
      uf: "SC"
    }
  end
end
