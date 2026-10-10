require "rails_helper"

RSpec.describe "Admin::ImageMigrationStatus", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.default }
  let(:admin) { create(:admin_user, :admin, tenant: tenant) }
  let(:other_tenant) { Tenant.create!(name: "Outra conta", slug: "outra-conta-#{SecureRandom.hex(3)}") }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  def attach_photo(habitation, filename)
    habitation.photos.attach(
      io: StringIO.new("bytes-#{filename}".b),
      filename: filename,
      content_type: "image/jpeg"
    )
    habitation.photos.attachments.find_by!(blob: ActiveStorage::Blob.find_by!(filename: filename))
  end

  def create_photo_asset(habitation:, status:, source_path:)
    VistaFileAsset.create!(
      vista_import_batch: VistaImportBatch.create!(dump_dir: "api:vista", status: "completed"),
      tenant_id: habitation.tenant_id,
      table_name: "API_FOTO",
      kind: "property_photo",
      status: status,
      source_path: source_path,
      filename: File.basename(source_path),
      habitation: habitation,
      codigo_imovel: habitation.codigo
    )
  end

  it "escopa toda a telemetria de migração à conta solicitante (image-migration-status-global-tenant-telemetry)" do
    own = create(:habitation, tenant: tenant, codigo: "TEN-A-1")
    own_attachment = attach_photo(own, "propria.jpg")
    foreign = create(:habitation, tenant: other_tenant, codigo: "TEN-B-1")
    attach_photo(foreign, "estrangeira-1.jpg")
    foreign_latest = attach_photo(foreign, "estrangeira-2.jpg")
    foreign_latest.update_column(:created_at, 1.hour.from_now)

    create_photo_asset(habitation: own, status: "failed", source_path: "telemetria/propria-falha.jpg")
    create_photo_asset(habitation: own, status: "downloaded", source_path: "telemetria/propria-ok.jpg")
    create_photo_asset(habitation: foreign, status: "failed", source_path: "telemetria/estrangeira-falha-1.jpg")
    create_photo_asset(habitation: foreign, status: "failed", source_path: "telemetria/estrangeira-falha-2.jpg")

    get admin_image_migration_status_path(format: :json)

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)

    expect(payload["migrated_images"]).to eq(1)
    expect(Time.zone.parse(payload["latest_attachment_at"]).to_i).to eq(own_attachment.created_at.to_i)
    expect(payload["file_asset_counts"]).to eq({ "failed" => 1, "downloaded" => 1 })
    expect(payload["failed_properties"]).to eq(1)
    expect(payload["failed_sample"]).to eq([own.id])
    expect(payload.dig("execution", "failed")).to eq(1)
  end

  it "renderiza o painel HTML com telemetria da conta" do
    own = create(:habitation, tenant: tenant, codigo: "TEN-A-2")
    attach_photo(own, "propria-html.jpg")

    get admin_image_migration_status_path

    expect(response).to have_http_status(:ok)
  end
end
