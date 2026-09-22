module Admin
  # Identidade do site público: marca, logo, favicon, paleta e modelo visual.
  # A plataforma interna (cores do admin, menu lateral) continua em Conta → Aparência.
  class PublicIdentitiesController < BaseController
    requires_permission :manage, :site_publico
    before_action :set_records

    def edit
    end

    def update
      saved = LayoutSetting.transaction do
        @layout_setting.update(layout_params) && update_theme!
      end

      if saved
        redirect_to edit_admin_public_identity_path, notice: "Identidade do site atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_records
      @layout_setting = LayoutSetting.instance
      @tenant = current_tenant
    end

    def layout_params
      params.fetch(:layout_setting, {}).permit(:site_name, :logo, :favicon, :custom_logo_css, :primary_color, :secondary_color, :accent_color)
    end

    def update_theme!
      theme = params.dig(:tenant, :public_site_theme).presence
      return true if theme.nil? || theme == @tenant.public_site_theme
      return true if @tenant.available_public_site_themes.key?(theme) && @tenant.update(public_site_theme: theme)

      @layout_setting.errors.add(:base, "Modelo visual inválido.")
      raise ActiveRecord::Rollback
    end
  end
end
