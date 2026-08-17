require "rails_helper"

RSpec.describe Vista::ApiPictureMaterializationService, type: :service do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  describe ".default_scope" do
    it "inclui unidade que usa fotos do empreendimento como fallback publico" do
      development = create(:habitation, codigo: "611", tipo: "Empreendimento", pictures: [])
      habitation = create(
        :habitation,
        pictures: [],
        fotos_empreendimento: [
          {
            "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/611/foto.jpg",
            "ordem" => 1
          }
        ],
        use_development_photos_flag: true,
        codigo_empreendimento: development.codigo,
        imovel_dwv: "Nao",
        address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
      )

      expect(described_class.default_scope).to include(habitation)
    end
  end

  describe "#call" do
    it "processa fotos de empreendimento quando a unidade usa esse fallback" do
      development = create(:habitation, codigo: "611", tipo: "Empreendimento", pictures: [])
      habitation = create(
        :habitation,
        pictures: [],
        fotos_empreendimento: [
          {
            "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/611/foto.jpg",
            "ordem" => 1
          }
        ],
        use_development_photos_flag: true,
        codigo_empreendimento: development.codigo,
        imovel_dwv: "Nao",
        address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
      )

      result = described_class.new(scope: Habitation.where(id: habitation.id), dry_run: true).call

      expect(result.properties_scanned).to eq(1)
      expect(result.pictures_scanned).to eq(1)
      expect(result.pending_download).to eq(1)
    end

    it "reenveia o arquivo quando o blob deterministico existe sem objeto no storage" do
      body = "conteudo da foto"
      filename = "foto.jpg"
      habitation = create(
        :habitation,
        codigo: "777",
        pictures: [
          {
            "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/777/#{filename}",
            "ordem" => 1
          }
        ],
        imovel_dwv: "Nao",
        address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
      )
      key = "vista/property_photo/777/#{filename}"
      blob = ActiveStorage::Blob.create_before_direct_upload!(
        key: key,
        filename: filename,
        byte_size: body.bytesize,
        checksum: Digest::MD5.base64digest(body),
        content_type: "image/jpeg",
        service_name: ActiveStorage::Blob.service.name
      )
      ActiveStorage::Attachment.create!(name: "photos", record: habitation, blob: blob)
      ActiveStorage::Blob.service.delete(key) if ActiveStorage::Blob.service.exist?(key)

      expect(ActiveStorage::Blob.service.exist?(key)).to be(false)
      allow_any_instance_of(described_class).to receive(:download).and_return(StringIO.new(body.b))

      result = described_class.new(scope: Habitation.where(id: habitation.id), dry_run: false).call

      expect(result.failed).to eq(0)
      expect(result.downloaded).to eq(1)
      expect(ActiveStorage::Blob.service.exist?(key)).to be(true)
      expect(habitation.reload.photos.attachments.map(&:blob)).to include(blob)
      expect(habitation.photo_ids_order).to include(habitation.photos.attachments.find_by(blob: blob).id)
    end
  end
end
