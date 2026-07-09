class Admin::AccessAuditLogsController < Admin::BaseController
  before_action -> { check_permission!(:view, :access_audit) }

  def index
    scope = current_tenant.access_audit_logs.includes(:admin_user).recent
    scoped_admin_user_ids = accessible_owner_ids(:access_audit)
    scope = scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids

    scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
    scope = scope.where(result: params[:result]) if params[:result].present?
    scope = scope.where(admin_user_id: params[:admin_user_id]) if params[:admin_user_id].present?
    if params[:profile_id].present?
      selected_profile = current_tenant.profiles.find_by(id: params[:profile_id])
      scope = scope.where(admin_user_id: scoped_admin_users(scoped_admin_user_ids).matching_access_profile(selected_profile).select(:id)) if selected_profile
    end
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
    @available_users = scoped_admin_users(scoped_admin_user_ids).order(:name)
    @available_profiles = available_access_profiles_for(@available_users)
    @available_device_types = current_tenant.access_audit_logs.where.not(device_type: [nil, ""]).distinct.order(:device_type).pluck(:device_type)
    @available_browsers = current_tenant.access_audit_logs.where.not(browser: [nil, ""]).distinct.order(:browser).pluck(:browser)
    @available_controllers = current_tenant.access_audit_logs.where.not(controller_name: [nil, ""]).distinct.order(:controller_name).pluck(:controller_name)
    @available_actions = current_tenant.access_audit_logs.where.not(action_name: [nil, ""]).distinct.order(:action_name).pluck(:action_name)
  end

  private

  def parsed_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def scoped_admin_users(scoped_admin_user_ids)
    users = current_tenant.admin_users.account_members
    scoped_admin_user_ids ? users.where(id: scoped_admin_user_ids) : users
  end

  def available_access_profiles_for(users)
    users = users.reorder(nil)
    profile_ids = users.where(horizontal_profile_id: nil).where.not(profile_id: nil).distinct.pluck(:profile_id)
    profile_ids += users.where.not(horizontal_profile_id: nil).distinct.pluck(:horizontal_profile_id)
    current_tenant.profiles.where(id: profile_ids.compact.uniq).order(Arel.sql("axis DESC, name ASC"))
  end
end
