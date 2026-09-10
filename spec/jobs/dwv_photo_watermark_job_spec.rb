require "rails_helper"

RSpec.describe DwvPhotoWatermarkJob do
  include ActiveJob::TestHelper

  it "materializa DWV uma vez, preserva ambiente e visibilidade e rejeita outras origens" do
    url = "https://dwvimagesv1.b-cdn.net/photo.png"
    habitation = create(:habitation, imovel_dwv: "Sim", pictures: [
      { "url" => url, "ambiente" => "Sala", "site_hidden" => true },
      { "url" => "http://127.0.0.1/private.png" },
      { "url" => "https://untrusted.example/photo.png" }
    ])
    setting = PropertySetting.instance(tenant: habitation.tenant)
    allow(PropertySetting).to receive(:instance).and_return(setting)
    allow(setting).to receive(:watermark_configured?).and_return(true)
    allow(Storage::Routing).to receive(:service_name_for).and_return("test")
    job = described_class.new
    allow(job).to receive(:download).and_return(File.binread(Rails.root.join("spec/fixtures/files/watermark.png")))

    2.times { job.perform(habitation.id, tenant_id: habitation.tenant_id) }
    attachments = habitation.reload.watermark_photos.attachments.includes(:blob).to_a
    expect(attachments.size).to eq(1)
    expect(attachments.first.blob.metadata).to include("source_url" => url, "ambiente" => "Sala")
    expect(habitation.site_hidden_photo_ids).to include(attachments.first.id)
    expect(job).to have_received(:download).once
    expect(enqueued_jobs.count { |entry| entry[:job] == HabitationPhotoWatermarkJob }).to eq(2)
  end

  it "não acessa um imóvel de outro tenant" do
    habitation = create(:habitation, imovel_dwv: "Sim")
    other = Tenant.create!(name: "Other DWV", slug: "dwv-other-#{SecureRandom.hex(4)}")
    job = described_class.new
    expect(job).not_to receive(:download)
    job.perform(habitation.id, tenant_id: other.id)
  end
  it "continua as demais fotos quando uma origem falha" do
    habitation = create(:habitation, imovel_dwv: "Sim", pictures: [{ "url" => "https://dwvimagesv1.b-cdn.net/broken.png" }, { "url" => "https://dwvimagesv1.b-cdn.net/good.png" }])
    setting = PropertySetting.instance(tenant: habitation.tenant)
    allow(PropertySetting).to receive(:instance).and_return(setting)
    allow(setting).to receive(:watermark_configured?).and_return(true)
    allow(Storage::Routing).to receive(:service_name_for).and_return("test")
    job = described_class.new
    allow(job).to receive(:download) do |uri|
      raise "Indisponível" if uri.path.include?("broken")
      File.binread(Rails.root.join("spec/fixtures/files/watermark.png"))
    end
    expect { job.perform(habitation.id, tenant_id: habitation.tenant_id) }.to raise_error("Indisponível")
    expect(habitation.reload.watermark_photos.count).to eq(1)
  end

end
