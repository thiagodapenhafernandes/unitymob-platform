module Admin
  class ThemePreferencesController < BaseController
    def update
      theme_owner = current_admin_user.login_identity
      requested_mode = theme_preference_params[:admin_theme_mode]

      if requested_mode.in?(AdminUser::ADMIN_THEME_MODES)
        theme_owner.update_columns(admin_theme_mode: requested_mode, updated_at: Time.current)
        respond_to do |format|
          format.html { redirect_back fallback_location: admin_root_path, notice: "Tema de exibição atualizado." }
          format.json { render json: theme_payload(requested_mode) }
        end
      else
        respond_to do |format|
          format.html { redirect_back fallback_location: admin_root_path, alert: "Não foi possível atualizar o tema de exibição." }
          format.json { render json: { error: "Tema de exibição inválido." }, status: :unprocessable_entity }
        end
      end
    end

    private

    def theme_preference_params
      params.require(:admin_user).permit(:admin_theme_mode)
    end

    def theme_payload(mode)
      layout_setting =
        if current_tenant.present?
          LayoutSetting.find_by(tenant: current_tenant) || LayoutSetting.instance(tenant: current_tenant)
        else
          LayoutSetting.platform_defaults
        end
      theme = layout_setting.effective_admin_theme(mode: mode)

      {
        mode: mode,
        theme_color: theme[:header],
        tokens: {
          admin_surface: theme[:surface],
          admin_surface_header: theme[:header],
          admin_workspace_bg: theme[:workspace],
          admin_sidebar_bg: theme[:sidebar],
          admin_primary: theme[:primary],
          admin_ink: theme[:ink]
        }
      }
    end
  end
end
