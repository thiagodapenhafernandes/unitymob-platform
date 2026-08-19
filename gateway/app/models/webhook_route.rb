# frozen_string_literal: true

class WebhookRoute < ApplicationRecord
  has_many :webhook_events, dependent: :nullify

  validates :provider, :client_key, :phone_number_id, :target_url, :forwarding_secret, presence: true
  validates :phone_number_id, uniqueness: { scope: :provider }
end
