# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  self.primary_key = "id"

  belongs_to :webhook_route, optional: true

  STATUSES = %w[received forwarded failed unrouted].freeze

  validates :provider, :event_type, :status, :received_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  def forwarded?
    status == "forwarded"
  end
end
