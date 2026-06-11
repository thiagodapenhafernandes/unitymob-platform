class UserMetaIntegration < ApplicationRecord
  belongs_to :admin_user
  has_many :meta_facebook_pages, dependent: :destroy
  has_many :meta_lead_forms, through: :meta_facebook_pages

  validates :access_token, presence: true
  validates :facebook_user_id, presence: true

  def expired?
    token_expires_at.present? && token_expires_at < Time.current
  end
end
