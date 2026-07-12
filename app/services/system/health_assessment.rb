module System
  class HealthAssessment
    DEFAULT_THRESHOLDS = {
      memory_available_warning: ENV.fetch("HEALTH_MEMORY_AVAILABLE_WARNING_PERCENT", "15").to_f,
      memory_available_critical: ENV.fetch("HEALTH_MEMORY_AVAILABLE_CRITICAL_PERCENT", "8").to_f,
      disk_warning: ENV.fetch("HEALTH_DISK_WARNING_PERCENT", "80").to_f,
      disk_critical: ENV.fetch("HEALTH_DISK_CRITICAL_PERCENT", "90").to_f,
      swap_warning_mb: ENV.fetch("HEALTH_SWAP_WARNING_MB", "512").to_i,
      http_warning_ms: ENV.fetch("HEALTH_HTTP_WARNING_MS", "1500").to_i,
      http_critical_ms: ENV.fetch("HEALTH_HTTP_CRITICAL_MS", "4000").to_i,
      application_errors_warning: ENV.fetch("HEALTH_APPLICATION_ERRORS_WARNING", "5").to_i,
      application_errors_critical: ENV.fetch("HEALTH_APPLICATION_ERRORS_CRITICAL", "20").to_i,
      integration_failures_critical: ENV.fetch("HEALTH_INTEGRATION_FAILURES_CRITICAL", "3").to_i
    }.freeze

    THRESHOLDS = DEFAULT_THRESHOLDS

    def self.call(runtime:, platform:)
      new(runtime:, platform:).call
    end

    def initialize(runtime:, platform:)
      @runtime = runtime.with_indifferent_access
      @platform = platform
      @thresholds = configured_thresholds
    end

    def call
      findings = platform_findings + runtime_findings
      {
        status: findings.map { |finding| finding[:severity] }.include?("critical") ? "critical" :
          (findings.any? ? "warning" : "healthy"),
        findings: findings,
        thresholds: thresholds
      }
    end

    private

    attr_reader :runtime, :platform, :thresholds

    def platform_findings
      findings = []
      errors = platform.fetch(:errors, {})
      error_count = errors[:application_open].to_i
      findings << finding("application_errors", error_count >= thresholds[:application_errors_critical] ? "critical" : "warning", "#{error_count} erros funcionais abertos") if error_count >= thresholds[:application_errors_warning]
      findings << finding("unassigned_errors", "warning", "#{errors[:unassigned_open]} erros funcionais sem tenant") if errors[:unassigned_open].to_i.positive?
      findings << finding("migrations_pending", "critical", "Existem migrations pendentes") if platform.dig(:release, :migrations_pending)

      failures = platform.fetch(:tenants, []).sum { |tenant| tenant[:integration_failures].to_i }
      if failures.positive?
        severity = failures >= thresholds[:integration_failures_critical] ? "critical" : "warning"
        findings << finding("integration_failures", severity, "#{failures} integrações degradadas")
      end
      findings
    end

    def runtime_findings
      findings = []
      memory = numeric(:memory_available_percent)
      findings << threshold_finding("memory_available", memory, lower: true, warning: thresholds[:memory_available_warning], critical: thresholds[:memory_available_critical], label: "Memória disponível") if memory
      disk = numeric(:disk_percent)
      findings << threshold_finding("disk", disk, warning: thresholds[:disk_warning], critical: thresholds[:disk_critical], label: "Uso de disco") if disk
      http = numeric(:http_ms)
      findings << threshold_finding("http_latency", http, warning: thresholds[:http_warning_ms], critical: thresholds[:http_critical_ms], label: "Latência HTTP") if http
      swap = numeric(:swap_used_mb)
      findings << finding("swap", "warning", "Swap em uso: #{swap.round} MB") if swap && swap >= thresholds[:swap_warning_mb]

      %i[puma solid_queue nginx database cache].each do |service|
        state = runtime[service].to_s
        findings << finding("service_#{service}", "critical", "#{service.to_s.humanize}: #{state.presence || 'sem estado'}") unless state.in?(%w[active ok])
      end
      findings.compact
    end

    def threshold_finding(code, value, warning:, critical:, label:, lower: false)
      breached_warning = lower ? value <= warning : value >= warning
      return unless breached_warning

      breached_critical = lower ? value <= critical : value >= critical
      finding(code, breached_critical ? "critical" : "warning", "#{label}: #{value.round(1)}")
    end

    def finding(code, severity, message)
      { code: code, severity: severity, message: message }
    end

    def numeric(key)
      Float(runtime[key])
    rescue ArgumentError, TypeError
      nil
    end

    def configured_thresholds
      return DEFAULT_THRESHOLDS unless ActiveRecord::Base.connection.data_source_exists?("system_health_settings")

      SystemHealthSetting.instance.thresholds
    rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid
      DEFAULT_THRESHOLDS
    end
  end
end
