require "rails_helper"

RSpec.describe Habitation, type: :model do
  describe "#public_image_sources" do
    before do
      allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
    end

    let(:vista_picture) do
      {
        "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/123/foto.jpg",
        "principal" => true
      }
    end

    it "prioriza fotos anexadas na base para imóveis vindos do Vista" do
      habitation = create(:habitation, codigo: unique_code("VISTA"), address_attributes: address_attributes("Vista 1"), pictures: [vista_picture], imovel_dwv: "Nao")
      habitation.photos.attach(
        io: StringIO.new("imagem"),
        filename: "foto.jpg",
        content_type: "image/jpeg"
      )

      first_source = habitation.public_image_sources.first

      expect(first_source["attachment"]).to be_present
      expect(first_source["url"]).to be_nil
    end

    it "prioriza fotos materializadas em vez de URL externa para imóveis DWV" do
      habitation = create(:habitation, codigo: unique_code("DWV"), address_attributes: address_attributes("DWV 1"), pictures: [vista_picture], imovel_dwv: "Sim")
      habitation.photos.attach(
        io: StringIO.new("imagem"),
        filename: "foto.jpg",
        content_type: "image/jpeg"
      )

      first_source = habitation.public_image_sources.first

      expect(first_source["attachment"]).to be_present
      expect(first_source["url"]).to be_nil
    end

    it "não inclui fotos anexadas marcadas como internas no conjunto público" do
      habitation = create(:habitation, codigo: unique_code("HIDDEN"), address_attributes: address_attributes("Hidden 1"), imovel_dwv: "Nao")
      habitation.photos.attach(
        io: StringIO.new("imagem um"),
        filename: "foto-um.jpg",
        content_type: "image/jpeg"
      )
      habitation.photos.attach(
        io: StringIO.new("imagem dois"),
        filename: "foto-dois.jpg",
        content_type: "image/jpeg"
      )
      attachments = habitation.photos.attachments.order(:id).to_a
      habitation.update!(site_hidden_photo_ids: [attachments.first.id])

      public_attachments = habitation.reload.public_image_sources.filter_map { |source| source["attachment"] }

      expect(public_attachments).to contain_exactly(attachments.second)
      expect(habitation.photos.attachments.map(&:id)).to contain_exactly(*attachments.map(&:id))
    end

    it "não inclui fotos da API Vista no conjunto público" do
      habitation = create(
        :habitation,
        codigo: unique_code("API"),
        address_attributes: address_attributes("API 1"),
        imovel_dwv: "Sim",
        pictures: [
          vista_picture,
          { "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/123/interna.jpg", "site_hidden" => true }
        ]
      )

      public_urls = habitation.public_image_sources.map { |source| source["url"] }

      expect(public_urls).to be_empty
      expect(habitation.pictures.size).to eq(2)
    end

    it "não usa fotos do empreendimento vinculado quando a unidade não optou por esse fallback" do
      development = create(
        :habitation,
        codigo: "EMP-IMG-1",
        tipo: "Empreendimento",
        address_attributes: address_attributes("Empreendimento 1"),
        pictures: [{ "url" => "https://cdn.saluteimoveis.com.br/empreendimento.jpg" }]
      )
      unit = create(
        :habitation,
        codigo: "UNIT-IMG-1",
        codigo_empreendimento: development.codigo,
        address_attributes: address_attributes("Unidade 1"),
        pictures: [],
        use_development_photos_flag: false
      )

      expect(unit.public_image_sources).to be_empty
      expect(unit.has_any_photo?).to be(false)
    end

    it "usa fotos do empreendimento vinculado quando a unidade optou pelo fallback e não tem fotos próprias" do
      development = create(
        :habitation,
        codigo: "EMP-IMG-2",
        tipo: "Empreendimento",
        address_attributes: address_attributes("Empreendimento 2"),
        pictures: [{ "url" => "https://cdn.saluteimoveis.com.br/empreendimento.jpg" }]
      )
      unit = create(
        :habitation,
        codigo: "UNIT-IMG-2",
        codigo_empreendimento: development.codigo,
        address_attributes: address_attributes("Unidade 2"),
        pictures: [],
        use_development_photos_flag: true
      )

      expect(unit.public_image_sources.map { |source| source["url"] }).to eq(["https://cdn.saluteimoveis.com.br/empreendimento.jpg"])
      expect(unit.has_any_photo?).to be(true)
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

  def unique_code(prefix)
    "#{prefix}-#{SecureRandom.hex(6)}"
  end
end
