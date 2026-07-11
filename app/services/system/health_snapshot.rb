require "json"

module System
  class HealthSnapshot
    DEFAULT_PATH = Rails.env.production? ? "/home/salute/deploy/shared/tmp/system_health.json" : Rails.root.join("tmp", "system_health.json").to_s

    def self.call
      new.call
    end

    def call
      data = JSON.parse(File.read(snapshot_path))
      data.deep_symbolize_keys
    rescue Errno::ENOENT, JSON::ParserError
      { status: "unknown", collected_at: nil }
    end

    private

    def snapshot_path
      Pathname.new(ENV.fetch("SYSTEM_HEALTH_SNAPSHOT_PATH", DEFAULT_PATH.to_s))
    end
  end
end
