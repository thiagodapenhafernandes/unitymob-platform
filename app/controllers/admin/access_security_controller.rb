class Admin::AccessSecurityController < Admin::BaseController
  before_action -> { check_permission!(:manage, :access_security) }

  def show
    load_dashboard
  end

  def update
    unless tenant_owner?
      redirect_to admin_access_security_path(anchor: "rules-pane"), alert: "Apenas o Dono da conta pode alterar configurações globais de segurança."
      return
    end

    Setting.set(AccessControl::Settings::ENFORCE_BROKER_IP_KEY, truthy?(params[:enforce_broker_ip_allowlist]).to_s, "Exigir IP permitido para corretores")
    Setting.set(AccessControl::Settings::ENFORCE_BROKER_DEVICE_KEY, truthy?(params[:enforce_broker_trusted_devices]).to_s, "Exigir aparelho confiável para corretores")

    redirect_to admin_access_security_path, notice: "Configurações de segurança atualizadas."
  end

  private

  def load_dashboard
    scoped_admin_user_ids = accessible_owner_ids(:access_security)

    rules_scope = current_tenant.access_control_rules.includes(:profile, :admin_user, :created_by).recent
    rules_scope = rules_scope.where(scope_type: "user", admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids
    rules_scope = rules_scope.where(rule_type: params[:rule_type]) if params[:rule_type].present?
    rules_scope = rules_scope.where(scope_type: params[:scope_type]) if params[:scope_type].present?
    rules_scope = rules_scope.where(profile_id: params[:rule_profile_id]) if params[:rule_profile_id].present?
    rules_scope = rules_scope.where(admin_user_id: params[:rule_admin_user_id]) if params[:rule_admin_user_id].present?
    rules_scope = rules_scope.where(enabled: ActiveModel::Type::Boolean.new.cast(params[:rule_enabled])) if params[:rule_enabled].present?
    rules_scope = rules_scope.where("ip_value ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:rule_ip].to_s)}%") if params[:rule_ip].present?

    devices_scope = current_tenant.trusted_devices.includes(admin_user: :profile).includes(:created_by).recent
    devices_scope = devices_scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids
    devices_scope = devices_scope.where(status: params[:device_status]) if params[:device_status].present?
    devices_scope = devices_scope.where(admin_user_id: params[:device_admin_user_id]) if params[:device_admin_user_id].present?
    devices_scope = devices_scope.joins(admin_user: :profile).where(profiles: { id: params[:device_profile_id] }) if params[:device_profile_id].present?
    devices_scope = devices_scope.where(last_ip: params[:device_ip]) if params[:device_ip].present?
    devices_scope = devices_scope.where(device_type: params[:device_type]) if params[:device_type].present?
    devices_scope = devices_scope.where(browser: params[:device_browser]) if params[:device_browser].present?

    @rules = rules_scope
    @trusted_devices = devices_scope.limit(120)
    @profiles = scoped_profile_relation(scoped_admin_user_ids).order(:name)
    @admin_users = scoped_admin_users(scoped_admin_user_ids).order(:name)
    @can_manage_global_access_security = tenant_owner?
    @access_scope_types = tenant_owner? ? AccessControlRule::SCOPE_TYPES : AccessControlRule::SCOPE_TYPES.slice("user")
    device_filter_scope = current_tenant.trusted_devices
    device_filter_scope = device_filter_scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids
    @available_device_types = device_filter_scope.where.not(device_type: [nil, ""]).distinct.order(:device_type).pluck(:device_type)
    @available_browsers = device_filter_scope.where.not(browser: [nil, ""]).distinct.order(:browser).pluck(:browser)
    @active_tab = access_security_active_tab
    @new_rule = current_tenant.access_control_rules.new(scope_type: tenant_owner? ? "global" : "user", rule_type: "allow_ip", enabled: true)
    @broker_ip_allowlist_enabled = AccessControl::Settings.broker_ip_allowlist_enabled?
    @broker_trusted_devices_enabled = AccessControl::Settings.broker_trusted_devices_enabled?
  end

  def access_security_active_tab
    return "devices" if params.slice(:device_status, :device_admin_user_id, :device_profile_id, :device_ip, :device_type, :device_browser).values.any?(&:present?)
    return "rules" if params.slice(:rule_type, :scope_type, :rule_profile_id, :rule_admin_user_id, :rule_enabled, :rule_ip).values.any?(&:present?)

    tenant_owner? ? "settings" : "rules"
  end

  def scoped_admin_users(scoped_admin_user_ids)
    users = current_tenant.admin_users.account_members
    scoped_admin_user_ids ? users.where(id: scoped_admin_user_ids) : users
  end

  def scoped_profile_relation(scoped_admin_user_ids)
    return current_tenant.profiles if scoped_admin_user_ids.nil?

    current_tenant.profiles.where(id: scoped_admin_users(scoped_admin_user_ids).select(:profile_id))
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
