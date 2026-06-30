class Admin::DataExportAuditLogsController < Admin::BaseController
  before_action -> { check_permission!(:view, :data_export_audit) }

  def index
    scope = current_tenant.data_export_audit_logs.includes(:admin_user).recent
    scoped_admin_user_ids = accessible_owner_ids(:data_export_audit)
    scope = scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids

    scope = scope.where(export_type: params[:export_type]) if params[:export_type].present?
    scope = scope.where(resource_name: params[:resource_name]) if params[:resource_name].present?
    scope = scope.where(admin_user_id: params[:admin_user_id]) if params[:admin_user_id].present?
    scope = scope.joins(:admin_user).where(admin_users: { profile_id: params[:profile_id] }) if params[:profile_id].present?
    scope = scope.where(ip: params[:ip]) if params[:ip].present?
    scope = scope.where(format: params[:data_format]) if params[:data_format].present?
    scope = scope.where("filename ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:filename].to_s)}%") if params[:filename].present?
    scope = scope.where("created_at >= ?", parsed_date(params[:start_date]).beginning_of_day) if parsed_date(params[:start_date])
    scope = scope.where("created_at <= ?", parsed_date(params[:end_date]).end_of_day) if parsed_date(params[:end_date])

    @logs = scope.paginate(page: params[:page], per_page: 40)
    stats_scope = scope.except(:order, :limit, :offset)
    @total_exports = stats_scope.count
    @csv_exports = stats_scope.where(export_type: "csv_export").count
    @print_reports = stats_scope.where(export_type: "print_report").count
    @total_records = stats_scope.sum(:record_count)
    @available_users = scoped_admin_users(scoped_admin_user_ids).order(:name)
    @available_profiles = current_tenant.profiles
      .where(id: @available_users.reselect(:profile_id))
      .order(:name)
    @available_formats = current_tenant.data_export_audit_logs.where.not(format: [nil, ""]).distinct.order(:format).pluck(:format)
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
end
