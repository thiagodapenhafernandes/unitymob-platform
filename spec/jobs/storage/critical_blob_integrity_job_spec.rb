require "rails_helper"

RSpec.describe Storage::CriticalBlobIntegrityJob do
  it "registra auditoria e erro quando um blob crítico não existe no storage" do
    tenant = Tenant.create!(name: "Tenant integrity #{SecureRandom.hex(3)}", slug: "tenant-integrity-#{SecureRandom.hex(3)}")
    setting = PropertySetting.create!(tenant: tenant)
    setting.watermark_image.attach(io: StringIO.new("watermark"), filename: "watermark.png", content_type: "image/png")
    attachment = setting.watermark_image.attachment
    blob = attachment.blob
    service = instance_double(ActiveStorage::Service)

    allow(Storage::ActiveStorageRegistry).to receive(:register_if_available!)
    allow(Storage::ProtectedBlobPolicy).to receive(:critical_attachment_scope).and_return(ActiveStorage::Attachment.where(id: attachment.id))
    allow(Storage::ActiveStorageRegistry).to receive(:fetch!).with(blob.service_name).and_return(service)
    allow(service).to receive(:exist?).with(blob.key).and_return(false)
    allow(Storage::BlobAuditRecorder).to receive(:record!)
    allow(ErrorEvent).to receive(:record!)

    result = described_class.perform_now

    expect(result).to include(checked: 1, missing: 1, failed: 0)
    expect(Storage::BlobAuditRecorder).to have_received(:record!).with(
      blob: blob,
      attachment: attachment,
      action: "critical_blob_missing",
      source: "critical_blob_integrity_job",
      metadata: hash_including(
        tenant_id: tenant.id,
        blob_id: blob.id,
        key: blob.key,
        filename: "watermark.png",
        service_name: blob.service_name,
        attachment_name: "watermark_image",
        record_type: "PropertySetting",
        record_id: setting.id
      )
    )
    expect(ErrorEvent).to have_received(:record!).with(
      an_instance_of(described_class::MissingCriticalBlob),
      source: "job",
      severity: "error",
      context: hash_including(
        report_source: "storage.critical_blob_integrity"
      )
    )
  end
end
