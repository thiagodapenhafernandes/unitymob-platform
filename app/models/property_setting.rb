class PropertySetting < ApplicationRecord
  DEFAULT_WATERMARK_SIZE_PERCENTAGE = 28
  CENTER_WATERMARK_SIZE_PERCENTAGE = 58
  DEFAULT_WATERMARK_OPACITY_PERCENTAGE = 100
  WATERMARK_SIZE_RANGE = 10..120
  WATERMARK_OPACITY_RANGE = 5..100

  WATERMARK_POSITIONS = {
    "bottom_left" => "Inferior esquerdo",
    "bottom_right" => "Inferior direito",
    "center" => "Centro"
  }.freeze

  has_one_attached :watermark_image

  validates :watermark_position, presence: true, inclusion: { in: WATERMARK_POSITIONS.keys }
  validates :watermark_size_percentage,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: WATERMARK_SIZE_RANGE.begin,
              less_than_or_equal_to: WATERMARK_SIZE_RANGE.end
            }
  validates :watermark_opacity_percentage,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: WATERMARK_OPACITY_RANGE.begin,
              less_than_or_equal_to: WATERMARK_OPACITY_RANGE.end
            }

  def self.instance
    setting = first_or_initialize(watermark_position: "bottom_left")
    setting.watermark_position ||= "bottom_left"
    setting.watermark_size_percentage ||= default_watermark_size_for(setting.watermark_position)
    setting.watermark_opacity_percentage ||= DEFAULT_WATERMARK_OPACITY_PERCENTAGE
    setting.save! if setting.new_record? || setting.changed?
    setting
  end

  def self.default_watermark_size_for(position)
    position == "center" ? CENTER_WATERMARK_SIZE_PERCENTAGE : DEFAULT_WATERMARK_SIZE_PERCENTAGE
  end

  def watermark_configured?
    watermark_image.attached?
  end
end
