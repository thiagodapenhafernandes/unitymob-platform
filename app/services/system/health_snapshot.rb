require "json"
require "net/http"

module System
  class HealthSnapshot
    SNAPSHOT_FILENAME = "system_health.json".freeze
    HTTP_TIMEOUT = 5
    MAX_FILE_AGE = ENV.fetch("SYSTEM_HEALTH_SNAPSHOT_MAX_AGE_SECONDS", "300").to_i.seconds

    def self.call
      new.call
    end

    def call
      data = JSON.parse(File.read(snapshot_path))
      snapshot = data.deep_symbolize_keys
      return snapshot if fresh_file_snapshot?(snapshot)

      live_snapshot
    rescue Errno::ENOENT, JSON::ParserError
      live_snapshot
    end

    private

    def snapshot_path
      configured_path = ENV["SYSTEM_HEALTH_SNAPSHOT_PATH"].presence
      return Pathname.new(configured_path) if configured_path

      default_snapshot_path
    end

    def default_snapshot_path
      return Rails.root.join("tmp", SNAPSHOT_FILENAME) unless Rails.env.production?

      shared_tmp = Rails.root.join("..", "..", "shared", "tmp").cleanpath
      shared_tmp.join(SNAPSHOT_FILENAME)
    end

    def fresh_file_snapshot?(snapshot)
      collected_at = Time.zone.parse(snapshot[:collected_at].to_s) if snapshot[:collected_at].present?
      collected_at.present? && collected_at >= MAX_FILE_AGE.ago
    rescue ArgumentError
      false
    end

    def live_snapshot
      healthz = healthz_result
      db = database_state
      cache = cache_state
      queue = queue_state
      {
        status: [healthz[:status], db, cache, queue].all?("ok") ? "healthy" : "unhealthy",
        collected_at: Time.current.iso8601,
        http_status: healthz[:http_status],
        http_ms: healthz[:http_ms],
        puma: healthz[:status] == "ok" ? "active" : "unknown",
        solid_queue: queue == "ok" ? "active" : "unknown",
        nginx: healthz[:status] == "ok" ? "active" : "unknown",
        database: db,
        cache: cache,
        memory_available_percent: memory_available_percent,
        puma_memory_mb: nil,
        swap_used_mb: swap_used_mb,
        disk_percent: disk_percent,
        load_1: load_average[0],
        load_5: load_average[1]
      }
    end

    def healthz_result
      uri = URI.join(application_url, "/healthz")
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
        http.get(uri.request_uri)
      end
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      { status: response.code.to_i == 200 ? "ok" : "fail", http_status: response.code.to_i, http_ms: elapsed }
    rescue StandardError => error
      Rails.logger.warn("[System::HealthSnapshot] healthz #{error.class}: #{error.message}")
      { status: "fail", http_status: 0, http_ms: nil }
    end

    def database_state
      ActiveRecord::Base.connection_pool.with_connection { |conn| conn.select_value("SELECT 1") }
      "ok"
    rescue StandardError => error
      Rails.logger.warn("[System::HealthSnapshot] database #{error.class}: #{error.message}")
      "unknown"
    end

    def cache_state
      return "ok" if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

      key = "system_health_snapshot:#{SecureRandom.hex(8)}"
      Rails.cache.write(key, "ok", expires_in: 30.seconds)
      Rails.cache.read(key) == "ok" ? "ok" : "unknown"
    rescue StandardError => error
      Rails.logger.warn("[System::HealthSnapshot] cache #{error.class}: #{error.message}")
      "unknown"
    ensure
      Rails.cache.delete(key) if key
    end

    def queue_state
      return "unknown" unless defined?(SolidQueue::Process)

      SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).exists? ? "ok" : "unknown"
    rescue StandardError => error
      Rails.logger.warn("[System::HealthSnapshot] solid_queue #{error.class}: #{error.message}")
      "unknown"
    end

    def memory_available_percent
      info = meminfo
      total = info["MemTotal"].to_i
      available = info["MemAvailable"].to_i
      return nil unless total.positive? && available.positive?

      ((available * 100.0) / total).round
    end

    def swap_used_mb
      info = meminfo
      total = info["SwapTotal"].to_i
      free = info["SwapFree"].to_i
      return nil unless total.positive?

      ((total - free) / 1024.0).round
    end

    def meminfo
      return {} unless File.exist?("/proc/meminfo")

      File.readlines("/proc/meminfo").each_with_object({}) do |line, values|
        key, value = line.split(":", 2)
        values[key] = value.to_s[/\d+/].to_i
      end
    rescue StandardError
      {}
    end

    def disk_percent
      output = IO.popen(%w[df -P /], &:read).to_s.lines.last.to_s
      Integer(output.split[4].to_s.delete("%"), exception: false)
    rescue StandardError
      nil
    end

    def load_average
      return [nil, nil] unless File.exist?("/proc/loadavg")

      first, second = File.read("/proc/loadavg").split.first(2)
      [Float(first, exception: false), Float(second, exception: false)]
    rescue StandardError
      [nil, nil]
    end

    def application_url
      ENV["APP_HOST"].presence || Rails.application.config.action_mailer.default_url_options[:host].to_s
    end
  end
end
