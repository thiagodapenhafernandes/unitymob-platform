require "rails_helper"

RSpec.describe Habitation, type: :model do
  describe "#public_image_sources" do
    let(:vista_picture) do
      {
        "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/123/foto.jpg",
        "principal" => true
      }
    end

    it "prioriza fotos anexadas na base para imóveis vindos do Vista" do
      habitation = create(:habitation, pictures: [vista_picture], imovel_dwv: "Nao")
      habitation.photos.attach(
        io: StringIO.new("imagem"),
        filename: "foto.jpg",
        content_type: "image/jpeg"
      )

      first_source = habitation.public_image_sources.first

      expect(first_source["attachment"]).to be_present
      expect(first_source["url"]).to include("/rails/active_storage/")
      expect(first_source["url"]).not_to include("vistahost.com.br")
    end

    it "mantem URLs JSON como prioridade para imóveis DWV" do
      habitation = create(:habitation, pictures: [vista_picture], imovel_dwv: "Sim")
      habitation.photos.attach(
        io: StringIO.new("imagem"),
        filename: "foto.jpg",
        content_type: "image/jpeg"
      )

      first_source = habitation.public_image_sources.first

      expect(first_source["url"]).to eq(vista_picture["url"])
    end

    it "não inclui fotos anexadas marcadas como internas no conjunto público" do
      habitation = create(:habitation, imovel_dwv: "Nao")
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

    it "não inclui fotos da API marcadas como internas no conjunto público" do
      habitation = create(
        :habitation,
        imovel_dwv: "Sim",
        pictures: [
          vista_picture,
          { "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/123/interna.jpg", "site_hidden" => true }
        ]
      )

      public_urls = habitation.public_image_sources.map { |source| source["url"] }

      expect(public_urls).to contain_exactly(vista_picture["url"])
      expect(habitation.pictures.size).to eq(2)
    end
  end
end
