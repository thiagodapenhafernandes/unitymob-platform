require "rails_helper"

RSpec.describe Storage::SafePurgeJob do
  it "registra serviços dinâmicos antes de purgar o blob" do
    blob = instance_double(ActiveStorage::Blob)
    attachments = double("attachments", exists?: false)

    allow(ActiveStorage::Blob).to receive(:find_by).with(id: 123).and_return(blob)
    allow(blob).to receive(:attachments).and_return(attachments)
    allow(blob).to receive(:purge)
    allow(Storage::BlobAuditRecorder).to receive(:record!)
    allow(Storage::ActiveStorageRegistry).to receive(:register_if_available!)

    described_class.perform_now(123)

    expect(Storage::ActiveStorageRegistry).to have_received(:register_if_available!)
    expect(Storage::BlobAuditRecorder).to have_received(:record!).with(
      blob: blob,
      action: "purge_started",
      source: "safe_purge_job"
    )
    expect(blob).to have_received(:purge)
  end

  it "não falha quando o blob já foi removido" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "não remove blob que voltou a ter anexos" do
    blob = instance_double(ActiveStorage::Blob)
    attachments = double("attachments", exists?: true)

    allow(ActiveStorage::Blob).to receive(:find_by).with(id: 123).and_return(blob)
    allow(blob).to receive(:attachments).and_return(attachments)
    allow(Storage::BlobAuditRecorder).to receive(:record!)
    allow(Storage::ProtectedBlobPolicy).to receive(:protected_attachments_for).with(blob).and_return([])
    allow(attachments).to receive(:first).and_return(nil)
    allow(attachments).to receive(:count).and_return(1)
    expect(blob).not_to receive(:purge)

    described_class.perform_now(123)

    expect(Storage::BlobAuditRecorder).to have_received(:record!).with(
      blob: blob,
      action: "purge_blocked_attached_blob",
      source: "safe_purge_job",
      attachment: nil,
      metadata: {
        attachment_count: 1,
        protected_attachments: []
      }
    )
  end

  it "bloqueia purge de blob protegido e registra o anexo crítico" do
    tenant = Tenant.create!(name: "Tenant safe purge #{SecureRandom.hex(3)}", slug: "tenant-safe-purge-#{SecureRandom.hex(3)}")
    setting = PropertySetting.create!(tenant: tenant)
    setting.watermark_image.attach(io: StringIO.new("watermark"), filename: "watermark.png", content_type: "image/png")
    attachment = setting.watermark_image.attachment
    blob = attachment.blob

    allow(ActiveStorage::Blob).to receive(:find_by).with(id: blob.id).and_return(blob)
    allow(Storage::BlobAuditRecorder).to receive(:record!)
    expect(blob).not_to receive(:purge)

    described_class.perform_now(blob.id)

    expect(Storage::BlobAuditRecorder).to have_received(:record!).with(
      blob: blob,
      action: "purge_blocked_protected_blob",
      source: "safe_purge_job",
      attachment: attachment,
      metadata: {
        attachment_count: 1,
        protected_attachments: [
          {
            id: attachment.id,
            name: "watermark_image",
            record_type: "PropertySetting",
            record_id: setting.id
          }
        ]
      }
    )
  end

  it "remove o registro quando o arquivo remoto já não existe" do
    blob = instance_double(ActiveStorage::Blob)
    attachments = double("attachments", exists?: false)

    allow(ActiveStorage::Blob).to receive(:find_by).with(id: 123).and_return(blob)
    allow(blob).to receive(:attachments).and_return(attachments)
    allow(blob).to receive(:purge).and_raise(ActiveStorage::FileNotFoundError)
    allow(blob).to receive(:destroy)
    allow(Storage::BlobAuditRecorder).to receive(:record!)

    described_class.perform_now(123)

    expect(Storage::BlobAuditRecorder).to have_received(:record!).with(
      blob: blob,
      action: "purge_missing_deleted",
      source: "safe_purge_job"
    )
    expect(blob).to have_received(:destroy)
  end
end
