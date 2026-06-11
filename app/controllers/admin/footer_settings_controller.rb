class Admin::FooterSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_footer_setting

  def edit
    # Ensure some items exist if list is empty
    @footer_setting.footer_links.build if @footer_setting.footer_links.empty?
    @footer_setting.footer_stores.build if @footer_setting.footer_stores.empty?
  end

  def update
    if @footer_setting.update(footer_setting_params)
      redirect_to edit_admin_footer_setting_path, notice: 'Configurações do rodapé atualizadas com sucesso!'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_footer_setting
    @footer_setting = FooterSetting.instance
  end

  def footer_setting_params
    params.require(:footer_setting).permit(
      :about_title, :about_text, :links_title, :stores_title, 
      :contact_title, :social_title, :whatsapp, :email, :copyright_text,
      footer_links_attributes: [:id, :label, :url, :position, :_destroy],
      footer_stores_attributes: [:id, :name, :address, :zip_code, :creci, :phone, :position, :_destroy],
      footer_social_links_attributes: [:id, :platform, :url, :enabled, :position, :_destroy]
    )
  end
end
