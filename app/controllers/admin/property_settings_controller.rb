module Admin
  class PropertySettingsController < BaseController
    before_action :require_admin!
    before_action :set_property_setting

    def edit
      @page_title = "Config Imóveis"
    end

    def update
      @property_setting.watermark_image.purge if remove_watermark_image?
      @property_setting.assign_attributes(property_setting_params)

      if @property_setting.save
        redirect_to edit_admin_property_setting_path, notice: "Configurações de imóveis atualizadas com sucesso."
      else
        @page_title = "Config Imóveis"
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_property_setting
      @property_setting = PropertySetting.instance
    end

    def property_setting_params
      params.require(:property_setting).permit(
        :watermark_position,
        :watermark_size_percentage,
        :watermark_opacity_percentage,
        :watermark_image
      )
    end

    def remove_watermark_image?
      ActiveModel::Type::Boolean.new.cast(params.dig(:property_setting, :remove_watermark_image))
    end
  end
end
