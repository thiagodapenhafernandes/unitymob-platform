# frozen_string_literal: true

# Assinatura de push de um AdminUser — Web Push (VAPID) para o PWA/navegador,
# ou device token nativo (APNs/FCM) para o app híbrido (Capacitor). No caso
# nativo, `endpoint` guarda o token em si; p256dh/auth só existem para "web".
class PushSubscription < ApplicationRecord
  NATIVE_PLATFORMS = %w[ios android].freeze

  belongs_to :admin_user

  validates :endpoint, presence: true, uniqueness: { scope: :admin_user_id }
  validates :p256dh, :auth, presence: true, if: :web?

  scope :active, -> { where(active: true) }

  def web?
    !native?
  end

  def native?
    platform.to_s.in?(NATIVE_PLATFORMS)
  end

  def keys_hash
    { p256dh: p256dh, auth: auth }
  end

  def apple_web_push?
    endpoint.to_s.include?("web.push.apple.com")
  end
end
