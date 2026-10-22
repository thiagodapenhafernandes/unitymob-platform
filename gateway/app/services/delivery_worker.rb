# frozen_string_literal: true

module Gateway
  class DeliveryWorker
    # Shared per host across Meta/WhatsApp and all worker processes: <= 200/minute.
    INTERVAL = 0.3
    MAX_ATTEMPTS = 10

    def self.tick
      delivered = 0
      pending = WebhookEvent.where(queue_finished_at: nil).where.not(queued_at: nil)
        .where('next_retry_at IS NULL OR next_retry_at <= ?', Time.now)
      DeliveryDestination.where(id: pending.select(:delivery_destination_id))
        .where('available_at <= ?', Time.now).order(:available_at).limit(100).pluck(:id).each do |id|
        DeliveryDestination.transaction do
          # NO KEY UPDATE serializes workers without blocking receipt FK inserts.
          destination = DeliveryDestination.lock('FOR NO KEY UPDATE SKIP LOCKED').find_by(id: id)
          next unless destination && destination.available_at <= Time.now

          event = WebhookEvent.where(delivery_destination: destination, queue_finished_at: nil)
            .where.not(queued_at: nil).where('next_retry_at IS NULL OR next_retry_at <= ?', Time.now).order(:id).first
          next unless event
          event.with_lock do
            next if event.queue_finished_at
            if event.forwarded? || event.attempts >= MAX_ATTEMPTS
              event.update!(queue_finished_at: Time.now)
              next
            end
            next if event.next_retry_at && event.next_retry_at > Time.now

            if event.webhook_route
              # Never send a queued receipt to a changed host or deactivated route.
              route = event.webhook_route.reload
              unless route.active? && URI(route.target_url).host.downcase == destination.host
                event.update!(status: 'failed', last_error: 'Queued destination changed or inactive', queue_finished_at: Time.now)
                next
              end
              EventForwarder.call(event: event, raw_body: event.raw_body)
            else
              UnroutedEventAlerter.call(event)
            end
            MirrorForwarder.call(event: event, raw_body: event.raw_body) if event.attempts <= 1
            finished = !event.webhook_route || event.forwarded? || event.attempts >= MAX_ATTEMPTS
            event.update!(queue_finished_at: Time.now) if finished
            destination.update!(available_at: event.last_error.to_s.start_with?('HTTP 429:') ? event.next_retry_at : Time.now + INTERVAL)
            delivered += 1
          end
        end
      end
      delivered
    end
  end
end
