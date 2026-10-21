require "rails_helper"

RSpec.describe "Preparação das fotos enviadas", type: :model do
  include ActiveJob::TestHelper

  let(:habitation) { create(:habitation) }
  let(:bytes) { File.binread(Rails.root.join("spec/fixtures/files/watermark.png")) }

  def upload(name)
    { io: StringIO.new(bytes), filename: name, content_type: "image/png" }
  end

  it "não prepara versões públicas de originais aguardando marca" do
    clear_enqueued_jobs
    habitation.watermark_photos.attach(20.times.map { |n| upload("foto-#{n}.png") })
    transforms = enqueued_jobs.select { |job| job[:job] == ActiveStorage::TransformJob }
    expect(transforms).to be_empty
    expect(habitation.reload.photos).not_to be_attached
  end

  it "continua preparando as três versões de fotos enviadas sem marca" do
    clear_enqueued_jobs
    habitation.photos.attach(upload("foto-publica.png"))
    expect(enqueued_jobs.count { |job| job[:job] == ActiveStorage::TransformJob }).to eq(3)
  end

  it "prioriza concluir fotos sobre o aquecimento, sem aumentar concorrência" do
    expect(HabitationPhotoWatermarkJob.new.priority).to be < Storage::TransformVariantJob.new.priority
    expect(HabitationPhotoWatermarkJob.new.priority).to be < ActiveStorage::TransformJob.new.priority
    expect(HabitationPhotoWatermarkJob.new.queue_name).to eq("media")
  end

  it "aplica a mesma regra em outra conta, sem misturar seus anexos" do
    other = Tenant.create!(name: "Outra conta de upload", slug: "outra-upload-#{SecureRandom.hex(4)}")
    other_habitation = create(:habitation, tenant: other)
    clear_enqueued_jobs
    other_habitation.watermark_photos.attach(upload("outra-conta.png"))
    expect(enqueued_jobs.none? { |job| job[:job] == ActiveStorage::TransformJob }).to be(true)
    expect(habitation.reload.watermark_photos).not_to be_attached
    expect(other_habitation.reload.photos).not_to be_attached
    expect(other_habitation.watermark_photos.count).to eq(1)
  end
end
