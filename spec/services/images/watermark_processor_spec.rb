require "rails_helper"

RSpec.describe Images::WatermarkProcessor do
  it "returns a processed attachable when a watermark is configured" do
    setting = PropertySetting.instance
    setting.update!(watermark_position: "center")
    setting.watermark_image.attach(png_upload("watermark.png", "120x60", "none", "white"))

    upload = png_upload("property.png", "320x220", "#d9e4ec", "#1f2937")

    result = described_class.call(upload, setting: setting)

    expect(result.attachable).to be_a(Hash)
    expect(result.attachable[:filename]).to eq("property.png")
    expect(result.attachable[:content_type]).to eq("image/png")
    expect(result.tempfile).to be_present
    expect(File.size(result.tempfile.path)).to be_positive
  ensure
    result&.tempfile&.close!
  end

  it "keeps the original upload when there is no watermark image" do
    setting = PropertySetting.instance
    setting.watermark_image.purge
    upload = png_upload("property.png", "320x220", "#d9e4ec", "#1f2937")

    result = described_class.call(upload, setting: setting)

    expect(result.attachable).to eq(upload)
    expect(result.tempfile).to be_nil
  end

  it "preserves storage missing errors when configured to surface failures" do
    watermark_attachment = double("watermark attachment")
    setting = instance_double(
      PropertySetting,
      watermark_configured?: true,
      watermark_image: watermark_attachment
    )
    upload = png_upload("property.png", "320x220", "#d9e4ec", "#1f2937")

    allow(watermark_attachment).to receive(:open).and_raise(ActiveStorage::FileNotFoundError)

    expect do
      described_class.call(upload, setting: setting, raise_errors: true)
    end.to raise_error(Images::WatermarkProcessor::MissingWatermarkError)
  end

  it "sizes watermarks from the configured percentage" do
    setting = PropertySetting.instance
    setting.update!(watermark_position: "center", watermark_size_percentage: 120)

    image = Struct.new(:width).new(1000)
    processor = described_class.new(png_upload("property.png", "1000x600", "#d9e4ec", "#1f2937"), setting: setting)

    expect(processor.send(:watermark_width_for, image)).to eq(1200)
  end

  it "mapeia as cinco posições para gravities do ImageMagick" do
    setting = PropertySetting.instance
    processor = described_class.new(png_upload("property.png", "320x220", "#d9e4ec", "#1f2937"), setting: setting)

    expect(PropertySetting::WATERMARK_POSITIONS.keys.index_with do |position|
      setting.watermark_position = position
      processor.send(:gravity)
    end).to eq(
      "top_left" => "NorthWest",
      "top_right" => "NorthEast",
      "bottom_left" => "SouthWest",
      "bottom_right" => "SouthEast",
      "center" => "Center"
    )
  end

  it "respeita percentuais e margens proporcionais mesmo em fotos pequenas" do
    setting = PropertySetting.instance
    setting.update!(watermark_position: "bottom_left", watermark_size_percentage: 28)
    processor = described_class.new(nil, setting: setting)
    image = Struct.new(:width).new(320)
    expect(processor.send(:watermark_width_for, image)).to eq(90)
    expect(processor.send(:geometry_for, image)).to eq("+11+11")
  end

  it "aplica a marca nos pixels esperados sem deslocamento ou sombra adicional" do
    setting = PropertySetting.instance
    setting.update!(watermark_position: "top_left", watermark_size_percentage: 25, watermark_opacity_percentage: 100)
    setting.watermark_image.attach(png_upload("marca.png", "120x60", "red", "red"))
    result = described_class.call(png_upload("foto.png", "320x220", "black", "black"), setting: setting, raise_errors: true)
    image = MiniMagick::Image.open(result.tempfile.path)
    pixels = image.get_pixels
    expect(pixels[12][12].first(3)).to eq([255, 0, 0])
    expect(pixels[0][0].first(3)).to eq([0, 0, 0])
    expect(pixels[12][92].first(3)).to eq([0, 0, 0])
  ensure
    image&.destroy!
    result&.tempfile&.close!
  end

  def png_upload(filename, size, background, fill)
    file = Tempfile.new([File.basename(filename, ".png"), ".png"])
    file.close
    system("magick", "-size", size, "xc:#{background}", "-fill", fill, "-draw", "rectangle 10,10 90,40", file.path, exception: true)
    Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: filename)
  end
end
