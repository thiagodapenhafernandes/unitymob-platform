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
      key = "vista/property_photo/tenant-#{Current.tenant.id}/777/#{filename}"
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

  describe "isolamento por conta (vista-api-photos-global-filename-blob-reuse)" do
    let(:tenant_a) { Tenant.default }
    let(:tenant_b) { Tenant.create!(name: "Vista B", slug: "vista-b-#{SecureRandom.hex(4)}") }

    def create_attached_photo(habitation, filename, body = "bytes-#{filename}")
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(body.b),
        filename: filename,
        content_type: "image/jpeg",
        service_name: ActiveStorage::Blob.service.name
      )
      habitation.photos.attach(blob)
      blob
    end

    it "gera chaves de storage segmentadas por conta" do
      habitation_a = create(:habitation, tenant: tenant_a, codigo: "VISTA-KEY-1")
      habitation_b = create(:habitation, tenant: tenant_b, codigo: "VISTA-KEY-1")

      key_a = Current.set(tenant: tenant_a) { described_class.new(dry_run: true).send(:storage_key_for, habitation_a, "foto.jpg") }
      key_b = Current.set(tenant: tenant_b) { described_class.new(dry_run: true).send(:storage_key_for, habitation_b, "foto.jpg") }

      expect(key_a).to include("tenant-#{tenant_a.id}")
      expect(key_b).to include("tenant-#{tenant_b.id}")
      expect(key_a).not_to eq(key_b)
    end

    it "não reutiliza blob de outra conta com o mesmo filename" do
      filename = "foto-colidida.jpg"
      habitation_a = create(:habitation, tenant: tenant_a, codigo: "VISTA-A-1")
      foreign_blob = create_attached_photo(habitation_a, filename)

      habitation_b = create(
        :habitation,
        tenant: tenant_b,
        codigo: "VISTA-B-1",
        pictures: [{ "url" => "https://cdn.outro-host.com.br/fotos/999/#{filename}", "ordem" => 1 }],
        imovel_dwv: "Nao"
      )
      allow_any_instance_of(described_class).to receive(:download).and_return(StringIO.new("bytes-b".b))

      result = Current.set(tenant: tenant_b) do
        described_class.new(scope: Habitation.where(id: habitation_b.id), dry_run: false).call
      end

      expect(result.failed).to eq(0)
      expect(result.reused).to eq(0)
      expect(result.downloaded).to eq(1)
      attached_blob = habitation_b.reload.photos.blobs.first
      expect(attached_blob).to be_present
      expect(attached_blob.id).not_to eq(foreign_blob.id)
      expect(attached_blob.key).to include("tenant-#{tenant_b.id}")
    end

    it "reutiliza blob já vinculado à mesma conta" do
      filename = "foto-mesma-conta.jpg"
      source = create(:habitation, tenant: tenant_a, codigo: "VISTA-A-2")
      own_blob = create_attached_photo(source, filename)

      target = create(
        :habitation,
        tenant: tenant_a,
        codigo: "VISTA-A-3",
        pictures: [{ "url" => "https://cdn.vista.com.br/fotos/888/#{filename}", "ordem" => 1 }],
        imovel_dwv: "Nao"
      )

      result = Current.set(tenant: tenant_a) do
        described_class.new(scope: Habitation.where(id: target.id), dry_run: false).call
      end

      expect(result.failed).to eq(0)
      expect(result.reused).to eq(1)
      expect(target.reload.photos.blobs.map(&:id)).to include(own_blob.id)
    end

    it "recusa anexar blob vinculado apenas a outra conta" do
      foreign_habitation = create(:habitation, tenant: tenant_b, codigo: "VISTA-B-9")
      foreign_blob = create_attached_photo(foreign_habitation, "foto-estrangeira.jpg")
      own_habitation = create(:habitation, tenant: tenant_a, codigo: "VISTA-A-9")

      service = Current.set(tenant: tenant_a) { described_class.new(dry_run: false) }

      expect do
        Current.set(tenant: tenant_a) { service.send(:attach_blob_once!, own_habitation, foreign_blob) }
      end.to raise_error(described_class::TenantMismatchError)
      expect(own_habitation.photos).not_to be_attached
    end
  end
end
