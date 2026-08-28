require "rails_helper"

RSpec.describe Storage::ProtectedBlobPolicy do
  it "identifica anexos críticos de configuração visual" do
    tenant = Tenant.create!(name: "Tenant protected #{SecureRandom.hex(3)}", slug: "tenant-protected-#{SecureRandom.hex(3)}")
    setting = PropertySetting.create!(tenant: tenant)
    setting.watermark_image.attach(io: StringIO.new("watermark"), filename: "watermark.png", content_type: "image/png")

    expect(described_class.protected_attachment?(setting.watermark_image.attachment)).to be(true)
    expect(described_class.protected_blob?(setting.watermark_image.blob)).to be(true)
  end

  it "não trata fotos comuns de imóvel como configuração crítica" do
    habitation = create(:habitation)
    habitation.photos.attach(io: StringIO.new("photo"), filename: "photo.jpg", content_type: "image/jpeg")

    expect(described_class.protected_attachment?(habitation.photos.attachments.last)).to be(false)
  end
end
