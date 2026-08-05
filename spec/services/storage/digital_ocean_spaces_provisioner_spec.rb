require "rails_helper"

RSpec.describe Storage::DigitalOceanSpacesProvisioner do
  class FakeSpacesClient
    attr_reader :calls

    def initialize(bucket_exists:)
      @bucket_exists = bucket_exists
      @calls = []
    end

    def head_bucket(bucket:)
      calls << [:head_bucket, bucket]
      return true if @bucket_exists

      raise Aws::S3::Errors::NoSuchBucket.new(nil, "not found")
    end

    def create_bucket(bucket:)
      calls << [:create_bucket, bucket]
      @bucket_exists = true
    end

    def put_bucket_cors(bucket:, cors_configuration:)
      calls << [:put_bucket_cors, bucket, cors_configuration]
    end

    def put_object(bucket:, key:, body:, content_type:)
      calls << [:put_object, bucket, key, body, content_type]
    end

    def delete_object(bucket:, key:)
      calls << [:delete_object, bucket, key]
    end
  end

  let(:tenant) { Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}") }
  let(:setting) do
    StorageIntegrationSetting.create!(
      tenant: tenant,
      photo_provider: "digital_ocean",
      document_provider: "digital_ocean",
      public_photos_enabled: true,
      do_spaces_bucket: "conexao-imobiliaria",
      do_spaces_region: "sfo3",
      do_spaces_endpoint: "https://sfo3.digitaloceanspaces.com",
      do_spaces_public_base_url: "https://conexao-imobiliaria.sfo3.digitaloceanspaces.com",
      do_spaces_access_key_id: "access",
      do_spaces_secret_access_key: "secret",
      s3_region: "us-east-1"
    )
  end

  it "cria o bucket, aplica CORS e valida upload quando o bucket não existe" do
    client = FakeSpacesClient.new(bucket_exists: false)
    allow(Aws::S3::Client).to receive(:new).and_return(client)

    result = described_class.new(setting: setting).call

    expect(result).to be_ok
    expect(result.created).to be(true)
    expect(client.calls.map(&:first)).to eq(%i[head_bucket create_bucket put_bucket_cors put_object delete_object])
    expect(result.message).to include("Bucket conexao-imobiliaria criado")
    expect(result.message).to include("sem CDN")
  end

  it "reusa bucket existente e ainda aplica CORS e teste de escrita" do
    client = FakeSpacesClient.new(bucket_exists: true)
    allow(Aws::S3::Client).to receive(:new).and_return(client)

    result = described_class.new(setting: setting).call

    expect(result).to be_ok
    expect(result.created).to be(false)
    expect(client.calls.map(&:first)).to eq(%i[head_bucket put_bucket_cors put_object delete_object])
    expect(result.message).to include("Bucket conexao-imobiliaria validado")
  end

  it "falha sem credenciais completas" do
    setting.update_column(:do_spaces_secret_access_key_ciphertext, nil)

    result = described_class.new(setting: setting).call

    expect(result).not_to be_ok
    expect(result.message).to include("Configuração DigitalOcean incompleta")
  end
end
