class Admin::NotificationTemplateSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }
  before_action :set_notification_template_setting, only: [:update, :destroy]

  def create
    setting = current_tenant.notification_template_settings.new(notification_template_setting_params)

    if setting.save
      redirect_to admin_whatsapp_integration_path, notice: "Template de notificação configurado."
    else
      redirect_to admin_whatsapp_integration_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  def update
    if @notification_template_setting.update(notification_template_setting_params)
      redirect_to admin_whatsapp_integration_path, notice: "Template de notificação atualizado."
    else
      redirect_to admin_whatsapp_integration_path, alert: @notification_template_setting.errors.full_messages.to_sentence
    end
  end

  def destroy
    @notification_template_setting.destroy
    redirect_to admin_whatsapp_integration_path, notice: "Template de notificação removido."
  end

  private

  def set_notification_template_setting
    @notification_template_setting = current_tenant.notification_template_settings.find(params[:id])
  end

  def notification_template_setting_params
    params.require(:notification_template_setting).permit(
      :channel,
      :purpose,
      :whatsapp_template_id,
      :active,
      variable_mapping: {}
    )
  end
end
