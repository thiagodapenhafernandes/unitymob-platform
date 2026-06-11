require "rails_helper"

RSpec.describe PropertySetting, type: :model do
  describe ".instance" do
    it "creates a singleton with the default watermark position" do
      setting = described_class.instance

      expect(setting).to be_persisted
      expect(setting.watermark_position).to eq("bottom_left")
      expect(setting.watermark_size_percentage).to eq(PropertySetting::DEFAULT_WATERMARK_SIZE_PERCENTAGE)
      expect(setting.watermark_opacity_percentage).to eq(PropertySetting::DEFAULT_WATERMARK_OPACITY_PERCENTAGE)
    end
  end

  it "validates predefined watermark positions" do
    setting = described_class.new(watermark_position: "top_left")

    expect(setting).not_to be_valid
    expect(setting.errors[:watermark_position]).to be_present
  end

  it "validates watermark size and opacity ranges" do
    setting = described_class.new(
      watermark_position: "center",
      watermark_size_percentage: 125,
      watermark_opacity_percentage: 0
    )

    expect(setting).not_to be_valid
    expect(setting.errors[:watermark_size_percentage]).to be_present
    expect(setting.errors[:watermark_opacity_percentage]).to be_present
  end
end
