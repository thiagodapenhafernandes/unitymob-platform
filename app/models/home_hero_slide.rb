require "image_processing/mini_magick"

class HomeHeroSlide < ApplicationRecord
  belongs_to :home_setting
  has_one_attached :image

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :image, presence: true

  scope :ordered, -> { order(:position, :id) }
  scope :active, -> { where(active: true) }

  OPTIMIZED_WIDTH = 1920
  OPTIMIZED_HEIGHT = 1080
  OPTIMIZED_QUALITY = 82

  def self.optimized_upload_file(uploaded_file)
    ImageProcessing::MiniMagick
      .source(uploaded_file.tempfile)
      .resize_to_limit(OPTIMIZED_WIDTH, OPTIMIZED_HEIGHT)
      .convert("jpg")
      .saver(quality: OPTIMIZED_QUALITY, strip: true, interlace: "JPEG")
      .call
  end

  def self.optimized_filename(uploaded_file)
    base_name = File.basename(uploaded_file.original_filename.to_s, ".*").presence || "hero-slide"
    "#{base_name.parameterize}-web.jpg"
  end

  def optimize_image!
    return unless image.attached?
    return if image.blob.metadata["optimized_for_web"]

    original_blob = image.blob
    optimized_file = nil
    image.blob.open do |source_file|
      optimized_file = ImageProcessing::MiniMagick
        .source(source_file)
        .resize_to_limit(OPTIMIZED_WIDTH, OPTIMIZED_HEIGHT)
        .convert("jpg")
        .saver(quality: OPTIMIZED_QUALITY, strip: true, interlace: "JPEG")
        .call
    end

    image.attach(
      io: optimized_file,
      filename: optimized_filename,
      content_type: "image/jpeg"
    )
    image.blob.update!(metadata: image.blob.metadata.merge("optimized_for_web" => true))
    original_blob.purge_later if original_blob != image.blob
  ensure
    optimized_file&.close
    optimized_file&.unlink
  end

  private

  def optimized_filename
    base_name = image.blob.filename.base.presence || "hero-slide"
    "#{base_name.parameterize}-web.jpg"
  end
end
