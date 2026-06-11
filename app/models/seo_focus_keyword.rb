class SeoFocusKeyword < ApplicationRecord
  belongs_to :seo_setting

  validates :keyword, presence: true
  validates :keyword, uniqueness: { scope: :seo_setting_id }

  before_validation :normalize_keyword

  scope :ordered, -> { order(:position, :keyword) }

  private

  def normalize_keyword
    self.keyword = keyword.to_s.squish.downcase
  end
end
