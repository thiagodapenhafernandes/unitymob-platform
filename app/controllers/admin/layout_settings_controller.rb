module Admin
  class LayoutSettingsController < ApplicationController
    layout 'admin'
    before_action :authenticate_admin_user!
    before_action :set_layout_setting

    def show
      render :edit
    end

    def edit
    end

    def update
      if @layout_setting.update(layout_setting_params)
        redirect_to edit_admin_layout_setting_path, notice: 'Configurações de layout atualizadas com sucesso.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_layout_setting
      @layout_setting = LayoutSetting.instance
    end

    def layout_setting_params
      params.require(:layout_setting).permit(:primary_color, :secondary_color, :accent_color, :logo, :favicon, :site_name)
    end
  end
end
