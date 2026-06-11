require "securerandom"

module Dwv
  class SyncLockService
    LOCK_KEY = "dwv_sync_lock".freeze
    DEFAULT_LEASE = 90.minutes
    DEFAULT_STALE_THRESHOLD = 3.minutes

    def initialize(lease_seconds: nil, stale_seconds: nil)
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

    private

    def ensure_lock_row!
      return if lock_record.present?

      Setting.create!(
        key: LOCK_KEY,
        value: {}.to_json,
        description: "Lock de concorrência para sincronização DWV"
      )
    rescue ActiveRecord::RecordNotUnique
      # corrida de criação: no-op, próxima leitura resolve
    end

    def lock_record
      @lock_record = Setting.find_by(key: LOCK_KEY)
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
      return false if locked_at > Time.current - @stale_threshold
      return false unless defined?(SolidQueue::ClaimedExecution)

      !SolidQueue::ClaimedExecution.joins(:job).where(solid_queue_jobs: { queue_name: "dwv" }).exists?
    rescue
      false
    end
  end
end
