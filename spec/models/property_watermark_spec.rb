require "rails_helper"

RSpec.describe PropertySetting do
  let(:setting) { PropertySetting.instance }

  it "rejeita conteúdo inválido, inclusive quando declara MIME de imagem" do
    %w[text/plain image/png].each do |type|
      setting.watermark_image = { io: StringIO.new("not an image"), filename: "marca.png", content_type: type }
      expect(setting).not_to be_valid
      expect(setting.errors[:watermark_image]).to be_present
    end
  end

  it "rejeita arquivos maiores que 5 MB" do
    setting.watermark_image = { io: StringIO.new("x" * (5.megabytes + 1)), filename: "marca.png", content_type: "image/png" }
    expect(setting).not_to be_valid
  end

  it "não exige baixar a marca antiga ao alterar outra configuração" do
    setting.watermark_image.attach(io: StringIO.new(File.binread(Rails.root.join("spec/fixtures/files/watermark.png"))), filename: "marca.png", content_type: "image/png")
    setting.reload.watermark_image.blob.delete
    expect(setting.update(watermark_opacity_percentage: 60)).to be(true)
  end
end
