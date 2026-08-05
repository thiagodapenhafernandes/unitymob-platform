require "rails_helper"

RSpec.describe "Admin::StorageIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  it "renderiza o workspace usando as métricas reais de armazenamento" do
    get admin_storage_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Armazenamento")
    expect(response.body).to include("anexos")
    expect(response.body).to include("blobs")
    expect(response.body).to include("Fotos públicas/CDN")
    progress = Nokogiri::HTML(response.body).at_css("progress.ax-progress__bar[data-storage-public-photo-publish-target='bar']")
    expect(progress).to be_present
    expect(progress["style"]).to be_nil
    expect(progress["max"]).to eq("100")
  end

  it "isola a configuração de armazenamento por conta" do
    own_setting = StorageIntegrationSetting.current(tenant: admin.tenant)
    own_setting.update!(photo_provider: "local", document_provider: "local", public_photos_enabled: false)
    other_tenant = Tenant.create!(name: "Outro storage", slug: "outro-storage-#{SecureRandom.hex(3)}")
    other_admin = create(:admin_user, :admin, tenant: other_tenant)
    sign_out admin
    sign_in other_admin

    get admin_storage_integration_path

    expect(response).to have_http_status(:ok)
    expect(StorageIntegrationSetting.current(tenant: other_tenant).public_photos_enabled?).to be(true)
    expect(StorageIntegrationSetting.where(tenant: [admin.tenant, other_tenant]).count).to eq(2)
  end

  it "não usa ENV de armazenamento como default de tenant não-default" do
    with_storage_env do
      default_tenant = Tenant.default
      other_tenant = Tenant.create!(name: "Conexão storage", slug: "conexao-storage-#{SecureRandom.hex(3)}")

      default_defaults = StorageIntegrationSetting.defaults_from_environment(tenant: default_tenant)
      other_defaults = StorageIntegrationSetting.defaults_from_environment(tenant: other_tenant)

      expect(default_defaults).to include(
        photo_provider: "digital_ocean",
        document_provider: "digital_ocean",
        do_spaces_bucket: "bucket-salute"
      )
      expect(other_defaults).to include(photo_provider: "local", document_provider: "local")
      expect(other_defaults).not_to include(:do_spaces_bucket, :do_spaces_access_key_id, :do_spaces_secret_access_key)
    end
  end

  it "provisiona DigitalOcean usando o nome do tenant quando a conta ainda aponta para bucket legado" do
    tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")
    tenant_admin = create(:admin_user, :admin, tenant: tenant)
    sign_out admin
    sign_in tenant_admin

    result = Storage::DigitalOceanSpacesProvisioner::Result.new(
      ok?: true,
      message: "Bucket conexao-imobiliaria criado no DigitalOcean Spaces.",
      created: true,
      configured: true
    )
    provisioner = instance_double(Storage::DigitalOceanSpacesProvisioner, call: result)
    allow(Storage::DigitalOceanSpacesProvisioner).to receive(:new).and_return(provisioner)
    allow(Storage::ActiveStorageRegistry).to receive(:register!)

    post provision_digital_ocean_admin_storage_integration_path,
         params: {
           storage_integration_setting: {
             photo_provider: "digital_ocean",
             document_provider: "digital_ocean",
             public_photos_enabled: "true",
             do_spaces_bucket: "imob",
             do_spaces_region: "sfo3",
             do_spaces_endpoint: "https://sfo3.digitaloceanspaces.com",
             do_spaces_access_key_id: "access",
             do_spaces_secret_access_key: "secret"
           }
         }

    setting = StorageIntegrationSetting.current(tenant: tenant)
    expect(response).to redirect_to(admin_storage_integration_path)
    expect(setting.do_spaces_bucket).to eq("conexao-imobiliaria")
    expect(setting.do_spaces_public_base_url).to eq("https://conexao-imobiliaria.sfo3.digitaloceanspaces.com")
    expect(Storage::DigitalOceanSpacesProvisioner).to have_received(:new).with(setting: setting)
    expect(Storage::ActiveStorageRegistry).to have_received(:register!).with(setting)
  end

  private

  def with_storage_env
    keys = %w[
      DO_SPACES_BUCKET
      DO_SPACES_ACCESS_KEY_ID
      DO_SPACES_SECRET_ACCESS_KEY
      DO_SPACES_PUBLIC_BASE_URL
      ACTIVE_STORAGE_SERVICE
    ]
    previous = keys.to_h { |key| [key, ENV[key]] }
    ENV["DO_SPACES_BUCKET"] = "bucket-salute"
    ENV["DO_SPACES_ACCESS_KEY_ID"] = "access-salute"
    ENV["DO_SPACES_SECRET_ACCESS_KEY"] = "secret-salute"

    original_service = Rails.configuration.active_storage.service
    Rails.configuration.active_storage.service = :do_spaces
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Rails.configuration.active_storage.service = original_service
  end
end
