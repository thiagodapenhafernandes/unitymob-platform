class Admin::FieldSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :field_settings) }
  def edit
    @enabled = FieldFeatureGate.field_checkin_enabled?
  end

  def update
    value = ActiveModel::Type::Boolean.new.cast(params[:enabled]) ? "true" : "false"
    Setting.set(FieldFeatureGate::SETTING_KEY, value)
    redirect_to edit_admin_field_settings_path, notice: "Feature check-in #{value == 'true' ? 'ativada' : 'desativada'}."
  end
end
