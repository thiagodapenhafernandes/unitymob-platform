class StapeCookiesController < ApplicationController
  skip_before_action :load_layout_settings

  def show
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    return head :forbidden if request.headers["Sec-Fetch-Site"] == "cross-site"

    setting = TrackingIntegrationSetting.current(tenant: public_tenant)
    options = { path: "/", secure: true, httponly: false, same_site: :lax }
    options[:domain] = request.host if request.host.include?(".") && !request.host.match?(/\A[\d.]+\z/)

    unless request.ssl? && lgpd_consent_accepted? && setting.google_tag_manager_enabled? && setting.stape_enabled?
      cookies.delete(:si_uid, **options)
      return head :no_content
    end

    uid = cookies[:si_uid].to_s
    uid = SecureRandom.uuid unless uid.match?(/\A[A-Za-z0-9_-]{1,48}\z/)
    cookies[:si_uid] = options.merge(value: uid, expires: 400.days.from_now)
    head :no_content
  end
end
