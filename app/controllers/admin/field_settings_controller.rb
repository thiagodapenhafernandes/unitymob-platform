class Admin::FieldSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :field_settings) }

  def edit
    load_field_settings
  end

  def update
    value = ActiveModel::Type::Boolean.new.cast(params[:enabled]) ? "true" : "false"
    Setting.set(FieldFeatureGate::SETTING_KEY, value)
    redirect_to edit_admin_field_settings_path, notice: "Feature check-in #{value == 'true' ? 'ativada' : 'desativada'}."
  end

  def unblock_agent
    user = current_tenant.admin_users.active.find(params[:admin_user_id])
    FieldFeatureGate.enable_agent!(user, tenant: current_tenant)

    redirect_to edit_admin_field_settings_path, notice: "#{user.name} liberado para check-in."
  end

  def block_agent
    user = current_tenant.admin_users.active.find(params[:admin_user_id])
    FieldFeatureGate.disable_agent!(user, tenant: current_tenant)

    redirect_to edit_admin_field_settings_path, notice: "#{user.name} bloqueado para check-in."
  end

  private

  def load_field_settings
    @enabled = FieldFeatureGate.field_checkin_enabled?
    @field_users = current_tenant.admin_users.active.order(:name)
    @stores = current_tenant.stores.active.order(:name)
    @blocked_agent_ids = FieldFeatureGate.disabled_agent_ids(tenant: current_tenant)
    @blocked_agents_count = @field_users.count { |user| @blocked_agent_ids.include?(user.id) }
  end
end
