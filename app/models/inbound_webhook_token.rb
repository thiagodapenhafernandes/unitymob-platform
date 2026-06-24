require "securerandom"

class InboundWebhookToken < ApplicationRecord
  TOKEN_BYTES = 32

  belongs_to :admin_user

  before_validation :ensure_token

  validates :token, presence: true, uniqueness: true
  validates :admin_user_id, uniqueness: true

  scope :enabled, -> { where(enabled: true) }

  def self.for_user(admin_user)
    find_or_create_by!(admin_user: admin_user)
  end

  def self.authenticate(raw_token)
    enabled.find_by(token: raw_token.to_s)
  end

  def regenerate!
    update!(token: self.class.generate_unique_token)
  end

  def record_received!
    update_columns(last_received_at: Time.current, updated_at: Time.current)
  end

  private

  def ensure_token
    self.token = self.class.generate_unique_token if token.blank?
  end

  def self.generate_unique_token
    loop do
      candidate = SecureRandom.urlsafe_base64(TOKEN_BYTES)
      break candidate unless exists?(token: candidate)
    end
  end
end
