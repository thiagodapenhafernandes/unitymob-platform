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
    notify_system_admins(assessment) unless assessment[:status] == "healthy"
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
    return "critical" if tenant[:integration_failures].to_i >= System::HealthAssessment::THRESHOLDS[:integration_failures_critical]

    tenant[:status] == "healthy" ? "healthy" : "warning"
  end

  def notify_system_admins(assessment)
    fingerprint = assessment[:findings].map { |finding| finding[:code] }.sort.join(":")
    cache_key = "system_health_monitor:#{Digest::SHA256.hexdigest(fingerprint)}"
    return unless Rails.cache.write(cache_key, Time.current.to_i, unless_exist: true, expires_in: ALERT_THROTTLE)

    body = assessment[:findings].first(3).map { |finding| finding[:message] }.join(" | ").truncate(240)
    AdminUser.where(super_admin: true, active: true).pluck(:id).each do |admin_user_id|
      Notifications::PushDispatcher.deliver(admin_user_id:, title: "Saúde da plataforma: #{assessment[:status]}", body:, url: "/admin/system/health", tag: "system_health")
    rescue StandardError => error
      Rails.logger.warn("[SYSTEM_HEALTH] push falhou admin_user_id=#{admin_user_id}: #{error.class}: #{error.message}")
    end
    notify_by_email(assessment)
  end

  def notify_by_email(assessment)
    recipients = ENV["SYSTEM_HEALTH_ALERT_EMAIL"].presence || ENV["ERROR_ALERT_EMAIL"]
    recipients = recipients.to_s.split(",").map(&:strip).reject(&:blank?)
    return if recipients.empty?

    SystemHealthAlertMailer.with(
      status: assessment[:status], findings: assessment[:findings], recipients: recipients
    ).degraded.deliver_later
  rescue StandardError => error
    Rails.logger.warn("[SYSTEM_HEALTH] e-mail falhou: #{error.class}: #{error.message}")
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
