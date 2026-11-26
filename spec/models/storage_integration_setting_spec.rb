require "rails_helper"

RSpec.describe StorageIntegrationSetting, type: :model do
  it "identifica o armazenamento legado nos novos uploads que usam credenciais de ambiente" do
    tenant = Tenant.new(name: "Conta padrão", slug: "default")
    setting = described_class.new(tenant: tenant, photo_provider: "digital_ocean", document_provider: "digital_ocean")
    allow(described_class).to receive(:environment_defaults_allowed?).with(tenant).and_return(true)
    allow(described_class).to receive(:digital_ocean_environment_ready?).and_return(true)
    allow(setting).to receive(:digital_ocean_ready?).and_return(false)

    expect(setting.photo_service_name).to eq(:do_spaces)
    expect(setting.document_service_name).to eq(:do_spaces)
  end

  it "preserva o serviço próprio quando as credenciais da conta estão disponíveis" do
    tenant = Tenant.new(id: 72, name: "Conta", slug: "conta")
    setting = described_class.new(tenant: tenant, photo_provider: "digital_ocean")
    allow(setting).to receive(:digital_ocean_ready?).and_return(true)

    expect(setting.photo_service_name).to eq(:do_spaces_db_tenant_72)
  end

  it "não usa credenciais de ambiente para outra conta" do
    tenant = Tenant.new(id: 73, name: "Outra conta", slug: "outra")
    setting = described_class.new(tenant: tenant, photo_provider: "digital_ocean")
    allow(described_class).to receive(:environment_defaults_allowed?).with(tenant).and_return(false)
    allow(described_class).to receive(:digital_ocean_environment_ready?).and_return(true)
    allow(setting).to receive(:digital_ocean_ready?).and_return(false)

    expect(setting.photo_service_name).to eq(:do_spaces_db_tenant_73)
  end

  it "gera nomes de serviço Active Storage distintos por tenant" do
    tenant_a = Tenant.create!(name: "Storage A", slug: "storage-a-#{SecureRandom.hex(3)}")
    tenant_b = Tenant.create!(name: "Storage B", slug: "storage-b-#{SecureRandom.hex(3)}")
    setting_a = described_class.new(tenant: tenant_a, photo_provider: "digital_ocean")
    setting_b = described_class.new(tenant: tenant_b, photo_provider: "digital_ocean")

    expect(setting_a.photo_service_name).to eq("do_spaces_db_tenant_#{tenant_a.id}".to_sym)
    expect(setting_b.photo_service_name).to eq("do_spaces_db_tenant_#{tenant_b.id}".to_sym)
    expect(setting_a.photo_service_name).not_to eq(setting_b.photo_service_name)
  end

  it "configura DigitalOcean Spaces com servico compativel" do
    tenant = Tenant.create!(name: "Storage DO", slug: "storage-do-#{SecureRandom.hex(3)}")
    setting = described_class.new(
      tenant: tenant,
      photo_provider: "digital_ocean",
      document_provider: "digital_ocean",
      do_spaces_bucket: "bucket-test",
      do_spaces_region: "sfo3",
      do_spaces_endpoint: "https://sfo3.digitaloceanspaces.com",
      do_spaces_access_key_id: "access-key",
      do_spaces_secret_access_key: "secret-key"
    )

    config = setting.active_storage_configurations.fetch(setting.photo_service_name)

    expect(config).to include(
      service: "DigitalOceanSpaces",
      request_checksum_calculation: "when_required",
      response_checksum_validation: "when_required"
    )
  end
  it "reuses the encryption key and still decrypts secrets written with the original derivation" do
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(
      "storage-integration-setting", ActiveSupport::MessageEncryptor.key_len
    )
    legacy = ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign("legacy-secret")
    setting = described_class.new(do_spaces_secret_access_key_ciphertext: legacy)

    expect(described_class.encryptor).to equal(described_class.encryptor)
    expect(setting.do_spaces_secret_access_key).to eq("legacy-secret")
    setting.do_spaces_secret_access_key = "updated-secret"
    expect(setting.do_spaces_secret_access_key).to eq("updated-secret")
  end

end
