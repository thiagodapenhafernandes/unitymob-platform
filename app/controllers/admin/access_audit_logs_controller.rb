class Admin::AccessAuditLogsController < Admin::BaseController
  before_action -> { check_permission!(:view, :access_audit) }

  def index
    scope = AccessAuditLog.includes(:admin_user).recent

    scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
    scope = scope.where(result: params[:result]) if params[:result].present?
    scope = scope.where(admin_user_id: params[:admin_user_id]) if params[:admin_user_id].present?
    scope = scope.joins(:admin_user).where(admin_users: { profile_id: params[:profile_id] }) if params[:profile_id].present?
    scope = scope.where(ip: params[:ip]) if params[:ip].present?
    scope = scope.where(device_type: params[:device_type]) if params[:device_type].present?
    scope = scope.where(browser: params[:browser]) if params[:browser].present?
    scope = scope.where(controller_name: params[:access_controller]) if params[:access_controller].present?
    scope = scope.where(action_name: params[:access_action]) if params[:access_action].present?
    scope = scope.where("path ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:path].to_s)}%") if params[:path].present?
    scope = scope.where("created_at >= ?", parsed_date(params[:start_date]).beginning_of_day) if parsed_date(params[:start_date])
    scope = scope.where("created_at <= ?", parsed_date(params[:end_date]).end_of_day) if parsed_date(params[:end_date])

    @logs = scope.paginate(page: params[:page], per_page: 40)
    stats_scope = scope.except(:order, :limit, :offset)
    @total_events = stats_scope.count
    @allowed_events = stats_scope.allowed.count
    @denied_events = stats_scope.denied.count
    @unique_ips = stats_scope.where.not(ip: nil).distinct.count(:ip)
    @available_users = AdminUser.order(:name)
    @available_profiles = Profile.order(:name)
    @available_device_types = AccessAuditLog.where.not(device_type: [nil, ""]).distinct.order(:device_type).pluck(:device_type)
    @available_browsers = AccessAuditLog.where.not(browser: [nil, ""]).distinct.order(:browser).pluck(:browser)
    @available_controllers = AccessAuditLog.where.not(controller_name: [nil, ""]).distinct.order(:controller_name).pluck(:controller_name)
    @available_actions = AccessAuditLog.where.not(action_name: [nil, ""]).distinct.order(:action_name).pluck(:action_name)
  end

  private

  def parsed_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
