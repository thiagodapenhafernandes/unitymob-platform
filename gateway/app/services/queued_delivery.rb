# frozen_string_literal: true

require 'digest'
require 'uri'

module Gateway
  # Uses the existing durable event store; historical rows are never enrolled.
  module QueuedDelivery
    module_function

    def enabled?
      ENV['GATEWAY_ASYNC_DELIVERY_ENABLED'] == 'true'
    end

    def identity(attributes)
      provider = attributes.fetch(:provider)
      payload = attributes.fetch(:payload)
      detail = if provider == 'meta' && attributes[:external_id].present?
        [attributes[:page_id], attributes[:form_id], attributes[:external_id]]
      else
        # Retain status transitions and template changes; ignore envelope delivery time.
        entries = Array(payload['entry']).map { |entry| entry.except('time') }
        canonical(payload.merge('entry' => entries))
      end
      Digest::SHA256.hexdigest(JSON.generate([provider, attributes[:webhook_route]&.id, attributes[:event_type], detail]))
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def persist(attributes)
      key = identity(attributes)
      existing = WebhookEvent.find_by(delivery_key: key)
      return existing if existing

      # Provider retries of old receipts must not replay the historical backlog.
      if attributes[:external_id].present?
        historical = WebhookEvent.where(delivery_key: nil, provider: attributes[:provider],
          webhook_route: attributes[:webhook_route], external_id: attributes[:external_id], event_type: attributes[:event_type])
        existing = historical.find do |event|
          identity(attributes.merge(payload: event.payload, page_id: event.page_id, form_id: event.form_id)) == key
        end
        return existing if existing
      end

      host = attributes[:webhook_route] ? URI(attributes[:webhook_route].target_url).host.downcase : '__unrouted__'
      destination = DeliveryDestination.find_by(host: host) ||
        DeliveryDestination.create_or_find_by!(host: host) { |record| record.available_at = Time.now }
      WebhookEvent.create_or_find_by!(delivery_key: key) do |event|
        event.assign_attributes(attributes.merge(queued_at: Time.now, delivery_destination: destination))
      end
    end
  end
end
