class HomeHeroSlide < ApplicationRecord
  belongs_to :home_setting
  has_one_attached :image do |attachment|
    Storage::PublicImageVariants.define(attachment, Storage::PublicImageVariants::HERO)
  end

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :image, presence: true
  validate :image_must_be_raster

  scope :ordered, -> { order(:position, :id) }
  scope :active, -> { where(active: true) }

  private

  def image_must_be_raster
    return unless image.attached?
    return if image.blob.variable? && image.blob.content_type != "image/gif"

    errors.add(:image, "deve ser uma imagem estática compatível (JPEG, PNG, WebP, AVIF ou HEIC)")
  end

end
