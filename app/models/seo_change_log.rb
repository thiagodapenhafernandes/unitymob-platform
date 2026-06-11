class SeoChangeLog < ApplicationRecord
  belongs_to :seo_setting
  belongs_to :admin_user, optional: true

  scope :recent, -> { order(created_at: :desc) }
end
