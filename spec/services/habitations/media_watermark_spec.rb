require "rails_helper"

RSpec.describe Habitations::MediaUpdater do
  let(:habitation) { create(:habitation) }
  let(:setting) { PropertySetting.instance(tenant: habitation.tenant) }
  let(:actor) { create(:admin_user, :admin, tenant: habitation.tenant) }
  let(:updater) { described_class.new(habitation: habitation, params: { habitation: { apply_photo_watermark: "1" } }, actor: actor, request: nil, property_setting: setting) }

  it "respeita o bloqueio de campo ao ler o parâmetro do formulário principal" do
    allow(Habitations::FieldLockPolicy).to receive(:for).with(actor).and_return(double(field_locked?: true))
    expect(updater.apply_photo_watermark_requested?).to be(false)
  end

  it "mantém um upload recuperável quando não é possível enfileirar" do
    setting.watermark_image.attach(io: StringIO.new(File.binread(Rails.root.join("spec/fixtures/files/watermark.png"))), filename: "marca.png", content_type: "image/png")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("foto"), filename: "foto.png", content_type: "image/png", metadata: { tenant_id: habitation.tenant_id })
    allow(HabitationPhotoWatermarkJob).to receive(:perform_later).and_return(false)
    expect { updater.attach_new_photos([blob.signed_id], apply_watermark: true) }.to raise_error(described_class::PhotoPublicationError)
    expect(habitation.reload.photos).not_to be_attached
    expect(habitation.watermark_photos.first.blob.metadata["watermark_status"]).to eq("failed")
  end

  it "não deixa um lote parcialmente anexado se a publicação sem marca falhar" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("foto"), filename: "foto.png", content_type: "image/png", metadata: { tenant_id: habitation.tenant_id })
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_attachment).and_return("https://example.test/photo")
    allow(Storage::PublicPropertyPhoto).to receive(:publish_attachment!).and_return(false)
    expect { updater.attach_new_photos([blob.signed_id], apply_watermark: false) }.to raise_error(described_class::PhotoPublicationError)
    expect(habitation.reload.photos).not_to be_attached
  end
  it "não publica sem marca quando a configuração foi removida após abrir o formulário" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("foto"), filename: "foto.png", content_type: "image/png", metadata: { tenant_id: habitation.tenant_id })
    updater.attach_new_photos([blob.signed_id], apply_watermark: true)
    expect(habitation.reload.photos).not_to be_attached
    expect(habitation.watermark_photos).to be_attached
  end

  it "preserva a falha para nova tentativa se a fila estiver indisponível ao retomar" do
    habitation.watermark_photos.attach(io: StringIO.new("foto"), filename: "foto.png", content_type: "image/png")
    photo = habitation.watermark_photos.first
    photo.blob.update!(metadata: { "watermark_status" => "failed" })
    allow(HabitationPhotoWatermarkJob).to receive(:perform_later).and_raise(SolidQueue::Job::EnqueueError)
    expect { updater.retry_watermark(photo.id) }.to raise_error(described_class::PhotoPublicationError)
    expect(photo.reload.blob.metadata["watermark_status"]).to eq("failed")
  end

end
