# frozen_string_literal: true

require "uri"

class WebhookMirror < ApplicationRecord
  PROVIDERS = %w[all whatsapp meta].freeze

  validates :name, :provider, :target_url, :forwarding_secret, presence: true
  validates :name, uniqueness: true
  validates :provider, inclusion: { in: PROVIDERS }
  validate :target_url_points_to_dev

  scope :active_for, ->(provider) { where(active: true, provider: ["all", provider.to_s]) }

  private

  def target_url_points_to_dev
    uri = URI.parse(target_url.to_s)
    return if uri.is_a?(URI::HTTPS) && uri.host == "dev.unitymob.com.br"

    errors.add(:target_url, "deve apontar para https://dev.unitymob.com.br")
  rescue URI::InvalidURIError
    errors.add(:target_url, "deve ser uma URL valida")
  end
end
