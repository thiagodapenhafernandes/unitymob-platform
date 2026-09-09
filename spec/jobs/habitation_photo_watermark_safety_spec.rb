require "rails_helper"

RSpec.describe HabitationPhotoWatermarkJob, type: :job do
  include ActiveJob::TestHelper
  let(:habitation) { create(:habitation) }
  let(:setting) { PropertySetting.instance(tenant: habitation.tenant) }
  let(:image_bytes) { File.binread(Rails.root.join("spec/fixtures/files/watermark.png")) }
  let(:attachment) { habitation.watermark_photos.attachments.first }

  before do
    setting.watermark_image.attach(io: StringIO.new(image_bytes), filename: "marca.png", content_type: "image/png")
    habitation.watermark_photos.attach(io: StringIO.new(image_bytes), filename: "foto.png", content_type: "image/png")
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!).and_return(true)
  end

  def process
    described_class.new.perform(habitation.id, [attachment.id], setting.id, tenant_id: habitation.tenant_id)
  end

  it "processa uma imagem real, libera apenas o resultado e não reaplica em nova execução" do
    original_id = attachment.blob_id
    expect(habitation.photos).not_to be_attached
    process
    attachment.reload
    marked_id = attachment.blob_id
    expect(marked_id).not_to eq(original_id)
    expect(attachment.name).to eq("photos")
    expect(attachment.blob.metadata["watermarked"]).to eq(true)
    expect(habitation.reload.watermark_photos).not_to be_attached
    process
    expect(attachment.reload.blob_id).to eq(marked_id)
    expect(Storage::PublicPropertyPhoto).to have_received(:publish_blob!).once
  end

  it "mantém privada a foto quando a conta desabilitou fotos públicas" do
    allow(Storage::PublicPropertyPhoto).to receive(:public_photos_enabled?).with(tenant: habitation.tenant).and_return(false)
    process
    expect(attachment.reload.name).to eq("photos")
    expect(Storage::PublicPropertyPhoto).not_to have_received(:publish_blob!)
  end

  it "não confunde marca ausente com original ausente e mantém a foto pendente" do
    setting.watermark_image.blob.delete
    expect { process }.to raise_error(Images::WatermarkProcessor::MissingWatermarkError, /marca indisponível/)
    expect(attachment.reload.blob.metadata["watermark_error"]).to include("marca indisponível")
    expect(habitation.reload.photos).not_to be_attached
  end

  it "rejeita configuração de outra conta e tenant explícito inexistente" do
    other = Tenant.create!(name: "Outra", slug: "outra-#{SecureRandom.hex(5)}")
    foreign_setting = PropertySetting.create!(tenant: other)
    expect { described_class.new.perform(habitation.id, [attachment.id], foreign_setting.id, tenant_id: habitation.tenant_id) }.to raise_error(ActiveRecord::RecordNotFound)
    Current.set(tenant: habitation.tenant) do
      expect { described_class.new.perform(habitation.id, [attachment.id], setting.id, tenant_id: -1) }.to raise_error(ArgumentError)
    end
    expect(habitation.reload.photos).not_to be_attached
  end

  it "limita a três execuções automáticas e permite diagnosticar a falha final" do
    setting.watermark_image.blob.delete
    args = [habitation.id, [attachment.id], setting.id]
    job = described_class.new(*args, tenant_id: habitation.tenant_id)
    expect { job.perform_now }.to have_enqueued_job(described_class)
    expect(attachment.reload.blob.metadata["watermark_status"]).to eq("retrying")
    job.executions = 2
    job.exception_executions = { "[Images::WatermarkProcessor::ProcessingError]" => 2 }
    expect { job.perform_now }.to raise_error(Images::WatermarkProcessor::MissingWatermarkError)
    expect(attachment.reload.blob.metadata["watermark_status"]).to eq("failed")
  end

  it "continua o lote quando uma foto falha" do
    attachment.blob.delete
    habitation.watermark_photos.attach(io: StringIO.new(image_bytes), filename: "segunda.png", content_type: "image/png")
    ids = habitation.watermark_photos.attachments.ids
    expect { described_class.new.perform(habitation.id, ids, setting.id, tenant_id: habitation.tenant_id) }.to raise_error(Images::WatermarkProcessor::ProcessingError)
    expect(habitation.reload.photos.count).to eq(1)
    expect(habitation.watermark_photos.count).to eq(1)
  end

  it "mantém o original pendente se publicar o resultado falhar e agenda limpeza do resultado" do
    original_id = attachment.blob_id
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!).and_raise(IOError)
    expect { process }.to raise_error(Images::WatermarkProcessor::ProcessingError)
    expect(attachment.reload.blob_id).to eq(original_id)
    expect(attachment.name).to eq("watermark_photos")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Storage::SafePurgeJob)
  end
  it "recarrega um anexo obsoleto sob lock antes de decidir reaplicar" do
    stale_attachment = ActiveStorage::Attachment.find(attachment.id)
    stale_attachment.blob
    process
    marked_id = attachment.reload.blob_id
    stale_attachment.with_lock do
      described_class.new.send(:process_attachment, stale_attachment, setting, habitation.tenant)
    end
    expect(stale_attachment.reload.blob_id).to eq(marked_id)
    expect(Storage::PublicPropertyPhoto).to have_received(:publish_blob!).once
  end

end
