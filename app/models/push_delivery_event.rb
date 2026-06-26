# frozen_string_literal: true

require "digest"
require "uri"

class PushDeliveryEvent < ApplicationRecord
  EVENT_TYPES = %w[
    provider_accepted
    provider_failed
    invalid_subscription
    no_active_subscription
    push_unavailable
    device_received
  ].freeze

  belongs_to :admin_user
  belongs_to :push_subscription, optional: true
  belongs_to :lead, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  def self.record!(event_type:, admin_user_id:, push_subscription: nil, tag: nil, endpoint: nil, user_agent: nil, **attrs)
    create!(
      attrs.merge(
        event_type: event_type,
        admin_user_id: admin_user_id,
        push_subscription: push_subscription,
        lead_id: lead_id_from_tag(tag),
        tag: tag,
        endpoint_host: endpoint_host(endpoint),
        endpoint_sha256: endpoint_sha256(endpoint),
        user_agent: user_agent
      )
    )
  rescue => e
    Rails.logger.warn("[PushDeliveryEvent] falha ao registrar evento #{event_type}: #{e.class} #{e.message}")
    nil
  end

  def self.lead_id_from_tag(tag)
    match = tag.to_s.match(/\Alead-(\d+)(?:-\d+)?\z/)
    match && match[1].to_i
  end

  def self.endpoint_host(endpoint)
    URI.parse(endpoint.to_s).host
  rescue URI::InvalidURIError
    nil
  end

  def self.endpoint_sha256(endpoint)
    return nil if endpoint.blank?

    Digest::SHA256.hexdigest(endpoint)
  end
end
