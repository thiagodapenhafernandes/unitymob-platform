require "socket"

class SystemHealthMonitorJob < ApplicationJob
  queue_as :checkin

  ALERT_THROTTLE = 30.minutes
  RETENTION_PERIOD = SystemHealthSnapshot::RETENTION_PERIOD

  def perform
    runtime = System::HealthSnapshot.call
    platform = System::PlatformHealthReport.call
    assessment = System::HealthAssessment.call(runtime:, platform:)
    collected_at = parse_time(runtime[:collected_at]) || Time.current

    persist_platform_snapshot(runtime, platform, assessment, collected_at)
    persist_tenant_snapshots(platform, collected_at)
    purge_expired_snapshots
    notify_system_admins(assessment, runtime:, platform:, collected_at:) unless assessment[:status] == "healthy"
  end

  private

  def persist_platform_snapshot(runtime, platform, assessment, collected_at)
    SystemHealthSnapshot.create!(
      status: assessment[:status], collected_at: collected_at,
      metrics: runtime.merge(errors: platform[:errors], findings: assessment[:findings])
    )
  end

  def persist_tenant_snapshots(platform, collected_at)
    platform.fetch(:tenants, []).each do |tenant|
      SystemHealthSnapshot.create!(
        tenant_id: tenant[:id], status: tenant_status(tenant), collected_at: collected_at,
        metrics: tenant.except(:id, :name, :slug, :status)
      )
    end
  end

  def tenant_status(tenant)
    return "unknown" if tenant[:status] == "inactive"
    threshold = SystemHealthSetting.instance.thresholds[:integration_failures_critical]
    return "critical" if tenant[:integration_failures].to_i >= threshold

    tenant[:status] == "healthy" ? "healthy" : "warning"
  end

  def notify_system_admins(assessment, runtime:, platform:, collected_at:)
    fingerprint = assessment[:findings].map { |finding| finding[:code] }.sort.join(":")
    cache_key = "system_health_monitor:#{Digest::SHA256.hexdigest(fingerprint)}"
    return unless Rails.cache.write(cache_key, Time.current.to_i, unless_exist: true, expires_in: ALERT_THROTTLE)

    body = assessment[:findings].first(3).map { |finding| finding[:message] }.join(" | ").truncate(240)
    AdminUser.where(super_admin: true, active: true).pluck(:id).each do |admin_user_id|
      Notifications::PushDispatcher.deliver(admin_user_id:, title: "Saúde da plataforma: #{assessment[:status]}", body:, url: "/admin/system/health", tag: "system_health")
    rescue StandardError => error
      Rails.logger.warn("[SYSTEM_HEALTH] push falhou admin_user_id=#{admin_user_id}: #{error.class}: #{error.message}")
    end
    notify_by_email(assessment, runtime:, platform:, collected_at:)
  end

  def notify_by_email(assessment, runtime:, platform:, collected_at:)
    recipients = ENV["SYSTEM_HEALTH_ALERT_EMAIL"].presence || ENV["ERROR_ALERT_EMAIL"]
    recipients = recipients.to_s.split(",").map(&:strip).reject(&:blank?)
    return if recipients.empty?

    SystemHealthAlertMailer.with(
      status: assessment[:status],
      findings: assessment[:findings],
      recipients: recipients,
      diagnostic: diagnostic_context(runtime:, platform:, collected_at:)
    ).degraded.deliver_later
  rescue StandardError => error
    Rails.logger.warn("[SYSTEM_HEALTH] e-mail falhou: #{error.class}: #{error.message}")
  end

  def diagnostic_context(runtime:, platform:, collected_at:)
    platform = platform.with_indifferent_access
    {
      environment: Rails.env,
      app_host: application_host,
      server_hostname: server_hostname,
      rails_root: Rails.root.to_s,
      collected_at: collected_at&.iso8601,
      release: platform[:release] || {},
      runtime: runtime_snapshot(runtime),
      platform_errors: platform[:errors] || {},
      degraded_tenants: degraded_tenants(platform),
      top_error_events: top_error_events
    }
  end

  def application_host
    ENV["APP_HOST"].presence || Rails.application.config.action_mailer.default_url_options[:host]
  rescue StandardError
    nil
  end

  def server_hostname
    Socket.gethostname
  rescue StandardError
    nil
  end

  def runtime_snapshot(runtime)
    runtime.with_indifferent_access.slice(
      :status, :http_status, :http_ms, :memory_available_percent, :puma_memory_mb,
      :disk_percent, :swap_used_mb, :load_1, :load_5, :puma, :solid_queue,
      :nginx, :database, :cache
    )
  end

  def degraded_tenants(platform)
    platform.fetch(:tenants, [])
      .select { |tenant| tenant[:status].to_s != "healthy" || tenant[:integration_failures].to_i.positive? || tenant[:open_errors].to_i.positive? }
      .sort_by { |tenant| [-(tenant[:open_errors].to_i + tenant[:integration_failures].to_i), tenant[:name].to_s] }
      .first(8)
      .map do |tenant|
        {
          id: tenant[:id],
          name: tenant[:name],
          slug: tenant[:slug],
          status: tenant[:status],
          open_errors: tenant[:open_errors].to_i,
          integration_failures: tenant[:integration_failures].to_i
        }
      end
  end

  def top_error_events
    return [] unless defined?(ErrorEvent) && ErrorEvent.storage_ready?

    ErrorEvent.unresolved
      .where.not(exception_class: System::PlatformHealthReport::TRAFFIC_NOISE_EXCEPTIONS)
      .recent
      .limit(5)
      .map { |event| serialize_error_event(event) }
  rescue StandardError => error
    Rails.logger.warn("[SYSTEM_HEALTH] falha ao carregar erros reais: #{error.class}: #{error.message}")
    []
  end

  def serialize_error_event(event)
    context = event.context || {}
    {
      id: event.id,
      exception_class: event.exception_class,
      message: event.message.to_s.truncate(500),
      source: event.source,
      severity: event.severity,
      tenant_id: event.tenant_id,
      occurrences_count: event.occurrences_count,
      first_seen_at: event.first_seen_at&.iso8601,
      last_seen_at: event.last_seen_at&.iso8601,
      request_id: context["request_id"],
      path: context["path"],
      method: context["method"],
      controller: context["controller"],
      action: context["action"],
      fingerprint: event.fingerprint
    }
  end

  def purge_expired_snapshots
    SystemHealthSnapshot.where("collected_at < ?", RETENTION_PERIOD.ago).delete_all
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
