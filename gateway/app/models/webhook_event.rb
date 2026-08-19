# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  belongs_to :webhook_route, optional: true

  STATUSES = %w[received forwarded failed unrouted].freeze

  validates :provider, :event_type, :status, :received_at, presence: true
  validates :status, inclusion: { in: STATUSES }
end
