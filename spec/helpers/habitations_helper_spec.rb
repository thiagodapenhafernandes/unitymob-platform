require "rails_helper"

RSpec.describe HabitationsHelper, type: :helper do
  describe "#catalog_property_image_urls" do
    before do
      allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
    end

    it "herda as fotos do empreendimento vinculado mesmo com a flag desativada, sem usar o payload de fotos da unidade" do
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

      urls = helper.catalog_property_image_urls(unit)
      expect(urls).to include("https://cdn.saluteimoveis.com.br/empreendimento.jpg")
      expect(urls).not_to include("https://cdn.saluteimoveis.com.br/payload-empreendimento.jpg")
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

  describe "#catalog_property_media_count" do
    it "conta mídia interna mesmo quando uma foto anexada está fora do site" do
      property = create(
        :habitation,
        codigo: "CATALOG-MEDIA-#{SecureRandom.hex(4)}",
        address_attributes: address_attributes("Imóvel com mídia interna")
      )
      property.photos.attach(io: StringIO.new("foto site"), filename: "foto-site.jpg", content_type: "image/jpeg")
      property.photos.attach(io: StringIO.new("foto interna"), filename: "foto-interna.jpg", content_type: "image/jpeg")
      attachments = property.photos.attachments.order(:id).to_a
      property.update!(site_hidden_photo_ids: [attachments.second.id])

      expect(helper.catalog_property_media_count(property.reload)).to eq(2)
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
