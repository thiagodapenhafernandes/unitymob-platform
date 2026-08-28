require "rails_helper"

RSpec.describe HabitationPhotoWatermarkJob, type: :job do
  include ActiveJob::TestHelper

  it "uses the isolated media queue" do
    expect(described_class.new.queue_name).to eq("media")
  end

  it "publishes the replacement and keeps the original blob available briefly" do
    suffix = SecureRandom.hex(3)
    tenant = Tenant.create!(name: "Tenant watermark #{suffix}", slug: "tenant-watermark-#{suffix}")
    habitation = create(:habitation, tenant: tenant)
    setting = PropertySetting.create!(tenant: tenant, watermark_position: "bottom_left")
    setting.watermark_image.attach(
      io: StringIO.new("watermark"),
      filename: "watermark.png",
      content_type: "image/png"
    )
    habitation.photos.attach(
      io: StringIO.new("original-photo"),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
    attachment = habitation.photos.attachments.last
    original_blob = attachment.blob
    processed_file = Tempfile.new(["watermarked", ".jpg"])
    processed_file.write("watermarked-photo")
    processed_file.rewind
    result = Images::WatermarkProcessor::Result.new(
      attachable: {
        io: processed_file,
        filename: "photo.jpg",
        content_type: "image/jpeg"
      },
      tempfile: processed_file
    )

    allow(Storage::ActiveStorageRegistry).to receive(:register_if_available!)
    allow(Images::WatermarkProcessor).to receive(:call).with(
      an_instance_of(described_class::BlobUpload),
      setting: setting,
      raise_errors: true
    ).and_return(result)
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!).and_return(true)

    expect do
      described_class.perform_now(habitation.id, [attachment.id], setting.id, tenant_id: tenant.id)
    end.to have_enqueued_job(Storage::SafePurgeJob).with(original_blob.id).at(
      be_within(2.seconds).of(described_class::ORIGINAL_BLOB_PURGE_DELAY.from_now)
    )

    attachment.reload
    expect(attachment.blob_id).not_to eq(original_blob.id)
    expect(attachment.blob.service_name).to eq(original_blob.service_name)
    expect(attachment.blob.metadata["watermarked"]).to be(true)
    expect(Storage::PublicPropertyPhoto).to have_received(:publish_blob!).with(
      attachment.blob,
      raise_errors: true
    )
    expect(Storage::ActiveStorageRegistry).to have_received(:register_if_available!)
    expect(ActiveStorage::Blob.exists?(original_blob.id)).to be(true)
  ensure
    processed_file&.close!
  end

  it "falha explicitamente quando a marca d'água configurada não pode ser aplicada" do
    suffix = SecureRandom.hex(3)
    tenant = Tenant.create!(name: "Tenant watermark failure #{suffix}", slug: "tenant-watermark-failure-#{suffix}")
    habitation = create(:habitation, tenant: tenant)
    setting = PropertySetting.create!(tenant: tenant, watermark_position: "center")
    setting.watermark_image.attach(
      io: StringIO.new("watermark"),
      filename: "watermark.png",
      content_type: "image/png"
    )
    habitation.photos.attach(
      io: StringIO.new("original-photo"),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
    attachment = habitation.photos.attachments.last
    original_blob = attachment.blob

    allow(Storage::ActiveStorageRegistry).to receive(:register_if_available!)
    allow(Images::WatermarkProcessor).to receive(:call).and_raise(
      Images::WatermarkProcessor::ProcessingError,
      "marca ausente"
    )
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!)

    expect do
      described_class.perform_now(habitation.id, [attachment.id], setting.id, tenant_id: tenant.id)
    end.to raise_error(Images::WatermarkProcessor::ProcessingError, /marca ausente/)

    expect(attachment.reload.blob_id).to eq(original_blob.id)
    expect(Storage::PublicPropertyPhoto).not_to have_received(:publish_blob!)
  end

  it "descarta sem falhar quando o arquivo original não existe mais no storage" do
    suffix = SecureRandom.hex(3)
    tenant = Tenant.create!(name: "Tenant watermark missing #{suffix}", slug: "tenant-watermark-missing-#{suffix}")
    habitation = create(:habitation, tenant: tenant)
    setting = PropertySetting.create!(tenant: tenant, watermark_position: "center")
    setting.watermark_image.attach(
      io: StringIO.new("watermark"),
      filename: "watermark.png",
      content_type: "image/png"
    )
    habitation.photos.attach(
      io: StringIO.new("original-photo"),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
    attachment = habitation.photos.attachments.last
    original_blob = attachment.blob

    allow(Storage::ActiveStorageRegistry).to receive(:register_if_available!)
    allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_raise(ActiveStorage::FileNotFoundError)
    allow(Storage::BlobAuditRecorder).to receive(:record!)
    allow(Images::WatermarkProcessor).to receive(:call)
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!)

    expect do
      described_class.perform_now(habitation.id, [attachment.id], setting.id, tenant_id: tenant.id)
    end.not_to raise_error

    expect(Storage::BlobAuditRecorder).to have_received(:record!).with(
      blob: original_blob,
      attachment: attachment,
      action: "watermark_source_missing",
      source: "habitation_photo_watermark_job",
      metadata: {
        error: "ActiveStorage::FileNotFoundError"
      }
    )
    expect(Images::WatermarkProcessor).not_to have_received(:call)
    expect(Storage::PublicPropertyPhoto).not_to have_received(:publish_blob!)
    expect(attachment.reload.blob_id).to eq(original_blob.id)
  end
end
