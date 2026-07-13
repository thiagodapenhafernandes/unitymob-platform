class ApplicationController < ActionController::Base
  before_action :apply_seo_redirect
  before_action :set_current_request_context
  before_action :set_current_public_tenant, unless: :administrative_request?
  before_action :set_admin_robots_header
  before_action :load_layout_settings
  helper_method :current_public_seo_setting, :lgpd_consent_accepted?, :admin_page_render_metrics, :admin_context_items,
                :public_tenant, :public_habitations

  LGPD_CONSENT_COOKIE = "salute_lgpd_consent".freeze

  def current_public_seo_setting
    return @current_public_seo_setting if defined?(@current_public_seo_setting)

    @current_public_seo_setting = Seo::PageTracker.track!(self)
  end

  def lgpd_consent_accepted?
    cookies[LGPD_CONSENT_COOKIE] == "accepted"
  end

  def admin_page_render_metrics
    started_at = @admin_render_started_at
    duration_ms =
      if @admin_render_duration_ms
        @admin_render_duration_ms
      elsif started_at
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)
      end

    {
      duration_ms: duration_ms,
      page: "#{controller_path}##{action_name}",
      status: response.status
    }.compact
  end

  def admin_context_items
    []
  end

  def public_tenant
    @public_tenant ||= Tenant.public_for(slug: public_tenant_slug)
  end

  def public_habitations
    public_tenant.habitations
  end

  private

  def set_current_public_tenant
    Current.tenant = public_tenant
  end

  def administrative_request?
    request.path.start_with?("/admin", "/field")
  end

  def public_tenant_slug
    params[:tenant_slug].presence || params[:tenant].presence
  end

  def set_current_request_context
    Thread.current[:setting_values_cache] = nil
    Current.request_ip = request.remote_ip
    Current.request_user_agent = request.user_agent.to_s.first(255)
    Current.request_metadata = {
      path: request.fullpath,
      method: request.request_method,
      controller: params[:controller],
      action: params[:action]
    }.compact
  end

  def apply_seo_redirect
    return unless request.get? || request.head?
    return if request.path.start_with?("/admin", "/field", "/rails/active_storage", "/assets", "/packs")

    lookup_path = seo_redirect_lookup_path
    lookup_paths = [lookup_path, request.path].uniq
    redirect_record = public_tenant.seo_redirects
      .active
      .where(from_path: lookup_paths)
      .order(Arel.sql(SeoRedirect.sanitize_sql_array(["CASE from_path WHEN ? THEN 0 ELSE 1 END", lookup_path])))
      .first
    return if redirect_record.blank?

    redirect_record.register_hit!
    redirect_to redirect_record.to_path, status: redirect_record.status_code, allow_other_host: true
  end

  def seo_redirect_lookup_path
    query = request.query_string.present? ? "?#{request.query_string}" : ""
    "#{request.path}#{query}"
  end

  def set_admin_robots_header
    return unless request.path.start_with?("/admin")

    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end

  def load_layout_settings
    return if request.path.start_with?("/field")

    admin_tenant = current_tenant if respond_to?(:current_tenant, true)
    tenant = request.path.start_with?("/admin") ? (admin_tenant || Tenant.public_for) : public_tenant
    @layout_setting = LayoutSetting.with_attached_logo.with_attached_favicon.find_by(tenant: tenant) || LayoutSetting.instance(tenant: tenant)
    return if request.path.start_with?("/admin")

    @home_setting = HomeSetting.instance(tenant: public_tenant)
    @footer_setting = FooterSetting.instance(tenant: public_tenant)
    @footer_links = Footer::QuickLinksService.call
    @footer_stores = public_tenant.stores.active.order(:id).to_a
    @footer_stores = @footer_setting.footer_stores.to_a if @footer_stores.empty?
    @footer_social_links = @footer_setting.footer_social_links.where(enabled: true).to_a
    @lead_capture_enabled = WebhookSetting.lead_capture_enabled?(tenant: public_tenant)
    @site_phone_settings = WhatsappBusinessIntegration.cached_site_phone_settings(public_tenant)
    @interest_settings = InterestIntelligence::Settings.new(@layout_setting)
    @tracking_setting = TrackingIntegrationSetting.current
  end
end
