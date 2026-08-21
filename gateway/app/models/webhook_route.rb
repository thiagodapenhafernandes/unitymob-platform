# frozen_string_literal: true

class WebhookRoute < ApplicationRecord
  self.primary_key = "id"

  has_many :webhook_events, dependent: :nullify

  validates :provider, :client_key, :target_url, :forwarding_secret, presence: true
  validates :phone_number_id, presence: true, if: :whatsapp?
  validates :page_id, presence: true, if: :meta?
  validates :phone_number_id, uniqueness: { scope: :provider }, if: :whatsapp?
  validates :page_id, uniqueness: { scope: %i[provider form_id] }, if: :meta?

  def whatsapp?
    provider.to_s == "whatsapp"
  end

  def meta?
    provider.to_s == "meta"
  end
end
