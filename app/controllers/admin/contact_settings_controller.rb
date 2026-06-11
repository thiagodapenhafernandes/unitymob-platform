class Admin::ContactSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_contact_setting

  def edit
  end

  def update
    if @contact_setting.update(contact_setting_params)
      redirect_to edit_admin_contact_setting_path, notice: 'Informações de contato atualizadas!'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_contact_setting
    @contact_setting = ContactSetting.instance
  end

  def contact_setting_params
    params.require(:contact_setting).permit(
      :whatsapp_primary,
      :whatsapp_secondary,
      :phone,
      :email_primary,
      :email_commercial,
      :address,
      :business_hours,
      :facebook_url,
      :instagram_url,
      :youtube_url,
      :linkedin_url
    )
  end
end
