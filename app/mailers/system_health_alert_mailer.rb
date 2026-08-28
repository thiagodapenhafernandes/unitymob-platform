class SystemHealthAlertMailer < ApplicationMailer
  def degraded
    @status = params[:status].to_s
    @findings = Array(params[:findings])
    @diagnostic = (params[:diagnostic] || {}).with_indifferent_access
    @release = (@diagnostic[:release] || {}).with_indifferent_access
    @runtime = (@diagnostic[:runtime] || {}).with_indifferent_access
    @platform_errors = (@diagnostic[:platform_errors] || {}).with_indifferent_access
    @degraded_tenants = Array(@diagnostic[:degraded_tenants]).map(&:with_indifferent_access)
    @app_host = @diagnostic[:app_host].presence || Rails.application.config.action_mailer.default_url_options[:host]
    @admin_base_url = admin_base_url
    @health_url = absolute_admin_path("/admin/system/health")
    @top_error_events = top_error_events
    recipients = Array(params[:recipients]).map(&:to_s).map(&:strip).reject(&:blank?)
    return if recipients.empty?

    mail(to: recipients, subject: "[UNITYMOB] Saúde da plataforma #{@status}: #{@app_host || Rails.env}")
  end

  private

  def admin_base_url
    host = @app_host.to_s.strip
    return nil if host.blank?

    normalized = host.match?(%r{\Ahttps?://}) ? host : "https://#{host}"
    normalized.chomp("/")
  end

  def top_error_events
    Array(@diagnostic[:top_error_events]).map do |event|
      event = event.with_indifferent_access
      event.merge(details_url: absolute_admin_path("/admin/system/error_events/#{event[:id]}"))
    end
  end

  def absolute_admin_path(path)
    return path if @admin_base_url.blank?

    "#{@admin_base_url}#{path}"
  end
end
