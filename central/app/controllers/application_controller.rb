class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :require_staff!
  before_action do
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "same-origin")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
  helper_method :current_staff, :current_staff_session
  def current_staff_session
    @current_staff_session ||= StaffSession.find_by(id: session[:staff_session_id], staff_id: session[:staff_id]) if session[:staff_session_id]
  end
  def current_staff
    return unless current_staff_session&.live?
    @current_staff ||= Staff.find_by(id: session[:staff_id], active: true, session_version: session[:staff_version])
  end
  private
  def require_staff!
    if current_staff&.activated_at
      current_staff_session.update_column(:last_activity_at, Time.current) unless %w[presence notifications].include?(controller_name) || action_name == 'updates'
      return
    end
    request.format.json? ? head(:unauthorized) : redirect_to(login_path)
  end
end
