# frozen_string_literal: true

module Gateway
  class RetryFailedEvents
    DEFAULT_LIMIT = 100
    DEFAULT_MAX_ATTEMPTS = 10

    Result = Struct.new(:retried, :forwarded, :failed, keyword_init: true)

    def self.call(limit: DEFAULT_LIMIT, max_attempts: DEFAULT_MAX_ATTEMPTS, now: Time.now, provider: nil)
      new(limit:, max_attempts:, now:, provider:).call
    end

    def initialize(limit:, max_attempts:, now:, provider: nil)
      @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
      @max_attempts = max_attempts.to_i.positive? ? max_attempts.to_i : DEFAULT_MAX_ATTEMPTS
      @now = now
      @provider = provider.presence
    end

    def call
      retried = 0
      forwarded = 0
      failed = 0

      retryable_events.each do |event|
        retried += 1
        if %w[grupozap tiktok].include?(event.provider)
          event.with_lock do
            EventForwarder.call(event:, raw_body: raw_body_for(event)) unless event.forwarded?
          end
        else
          EventForwarder.call(event:, raw_body: raw_body_for(event))
        end
        event.reload.forwarded? ? forwarded += 1 : failed += 1
      end

      Result.new(retried:, forwarded:, failed:)
    end

    private

    attr_reader :limit, :max_attempts, :now, :provider

    def retryable_events
      scope = provider ? WebhookEvent.where(provider: provider) : WebhookEvent.all
      scope
        .includes(:webhook_route)
        .where("webhook_events.status = 'failed' OR (webhook_events.provider IN ('grupozap', 'tiktok') AND webhook_events.status = 'received' AND webhook_events.received_at <= ?)", now - 60)
        .where("attempts < ?", max_attempts)
        .where("next_retry_at IS NULL OR next_retry_at <= ?", now)
        .where.not(webhook_route_id: nil)
        .joins(:webhook_route)
        .where(webhook_routes: { active: true })
        .order(Arel.sql("COALESCE(webhook_events.next_retry_at, webhook_events.received_at) ASC"))
        .limit(limit)
    end

    def raw_body_for(event)
      event.raw_body.to_s.empty? ? JSON.generate(event.payload || {}) : event.raw_body
    end
  end
end
