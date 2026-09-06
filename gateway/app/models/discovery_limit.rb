class DiscoveryLimit < ApplicationRecord
  def self.allow?(key, limit:, period:)
    now = Time.now.utc
    bucket = now.to_i / period
    digest = Gateway::Discovery.digest("rate:#{key}:#{bucket}")
    record = create_or_find_by!(key: digest) { |row| row.expires_at = Time.at((bucket + 1) * period).utc }
    record.with_lock do
      return false if record.hits >= limit
      record.update!(hits: record.hits + 1)
    end
    true
  end
end
