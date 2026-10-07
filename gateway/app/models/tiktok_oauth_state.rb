class TiktokOauthState < ApplicationRecord
  validates :state_digest, :return_url, :expires_at, presence: true
end
