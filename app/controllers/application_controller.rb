class ApplicationController < ActionController::Base
  before_action :apply_seo_redirect
  before_action :set_current_request_context
  before_action :set_admin_robots_header
  before_action :load_layout_settings
  helper_method :current_public_seo_setting, :lgpd_consent_accepted?

  LGPD_CONSENT_COOKIE = "salute_lgpd_consent".freeze

  def current_public_seo_setting
    return @current_public_seo_setting if defined?(@current_public_seo_setting)

    @current_public_seo_setting = Seo::PageTracker.track!(self)
  end

  def lgpd_consent_accepted?
    cookies[LGPD_CONSENT_COOKIE] == "accepted"
  end

  private

  def set_current_request_context
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
    return if request.path.start_with?("/admin", "/rails/active_storage", "/assets", "/packs")

    redirect_record = SeoRedirect.active.find_by(from_path: seo_redirect_lookup_path) ||
                      SeoRedirect.active.find_by(from_path: request.path)
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
    @layout_setting = LayoutSetting.instance
    return if request.path.start_with?("/admin")

    @home_setting = HomeSetting.instance
    @footer_setting = FooterSetting.instance
    @footer_links = Footer::QuickLinksService.call
    @footer_stores = Store.active.order(:id)
    @footer_stores = FooterStore.all if @footer_stores.empty?
    @footer_social_links = FooterSocialLink.where(enabled: true)
  end
end
