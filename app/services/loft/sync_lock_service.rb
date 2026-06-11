require "securerandom"

module Loft
  class SyncLockService
    DEFAULT_LEASE = 90.minutes
    DEFAULT_STALE_THRESHOLD = 3.minutes

    def initialize(lock_key:, lease_seconds: nil, stale_seconds: nil)
      @lock_key = lock_key.to_s
      @lease = lease_seconds.to_i.positive? ? lease_seconds.to_i.seconds : DEFAULT_LEASE
      @stale_threshold = stale_seconds.to_i.positive? ? stale_seconds.to_i.seconds : DEFAULT_STALE_THRESHOLD
    end

    def acquire
      ensure_lock_row!

      owner_token = nil
      lock_record.with_lock do
        payload = parse_payload(lock_record.value)
        locked_until = parse_time(payload["locked_until"])

        if locked_until.present? && locked_until > Time.current && !stale_lock?(payload)
          owner_token = nil
        else
          owner_token = SecureRandom.uuid
          lock_record.update!(
            value: {
              owner: owner_token,
              locked_at: Time.current.iso8601,
              locked_until: (Time.current + @lease).iso8601
            }.to_json
          )
        end
      end

      owner_token
    end

    def release(owner_token)
      return if owner_token.blank?

      ensure_lock_row!

      lock_record.with_lock do
        payload = parse_payload(lock_record.value)
        return unless payload["owner"] == owner_token

        lock_record.update!(value: {}.to_json)
      end
    end

    def refresh(owner_token)
      return false if owner_token.blank?

      ensure_lock_row!

      refreshed = false
      lock_record.with_lock do
        payload = parse_payload(lock_record.value)
        return false unless payload["owner"] == owner_token

        lock_record.update!(
          value: payload.merge(
            "locked_at" => Time.current.iso8601,
            "locked_until" => (Time.current + @lease).iso8601
          ).to_json
        )
        refreshed = true
      end

      refreshed
    end

    private

    def ensure_lock_row!
      return if lock_record.present?

      Setting.create!(
        key: @lock_key,
        value: {}.to_json,
        description: "Lock de concorrência para sincronização Loft"
      )
    rescue ActiveRecord::RecordNotUnique
      # corrida de criação: no-op
    end

    def lock_record
      @lock_record = Setting.find_by(key: @lock_key)
    end

    def parse_payload(raw)
      parsed = JSON.parse(raw.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def parse_time(raw)
      return nil if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def stale_lock?(payload)
      locked_at = parse_time(payload["locked_at"])
      return false if locked_at.blank?

      locked_at <= Time.current - @stale_threshold
    rescue StandardError
      false
    end
  end
end
