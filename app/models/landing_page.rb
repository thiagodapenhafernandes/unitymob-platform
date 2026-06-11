class LandingPage < ApplicationRecord
  extend FriendlyId
  friendly_id :title, use: :slugged

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true

  # Ensure filter_params is always a hash
  after_initialize :set_default_filter_params, if: :new_record?

  scope :active, -> { where(active: true) }

  private

  def set_default_filter_params
    self.filter_params ||= {}
  end
end
