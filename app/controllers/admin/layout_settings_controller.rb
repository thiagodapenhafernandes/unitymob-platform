module Admin
  # Herda a base do admin: helpers do layout/sidebar (tenant_owner?,
  # current_tenant, can?) e as políticas padrão de acesso.
  class LayoutSettingsController < BaseController
    before_action :authenticate_admin_user!
    requires_permission :manage, :conta
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
      attributes = params.require(:layout_setting).permit(
        :admin_surface_color,
        :admin_header_color,
        :admin_workspace_color,
        :admin_sidebar_color,
        :admin_primary_color,
        :admin_ink_color,
        :admin_area_name,
        admin_menu_section_colors: {}
      )
      normalize_admin_menu_section_colors(attributes)
      attributes
    end

    def normalize_admin_menu_section_colors(attributes)
      return unless attributes.key?(:admin_menu_section_colors)

      attributes[:admin_menu_section_colors] = LayoutSetting.normalized_admin_menu_section_styles(attributes[:admin_menu_section_colors])
    end
  end
end
