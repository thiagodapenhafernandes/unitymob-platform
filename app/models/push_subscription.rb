# frozen_string_literal: true

# Assinatura Web Push (VAPID) de um AdminUser.
# Cada device/browser gera uma subscription única (endpoint+keys).
class PushSubscription < ApplicationRecord
  belongs_to :admin_user

  validates :endpoint, presence: true, uniqueness: { scope: :admin_user_id }
  validates :p256dh, :auth, presence: true

  scope :active, -> { where(active: true) }

  def keys_hash
    { p256dh: p256dh, auth: auth }
  end

  def apple_web_push?
    endpoint.to_s.include?("web.push.apple.com")
  end
end
