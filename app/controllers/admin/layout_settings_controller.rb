module Admin
  # Herda a base do admin: helpers do layout/sidebar (tenant_owner?,
  # current_tenant, can?) e as políticas padrão de acesso.
  class LayoutSettingsController < BaseController
    before_action :authenticate_admin_user!
    before_action -> { check_permission!(:manage, :marketing) }
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
        :primary_color,
        :secondary_color,
        :accent_color,
        :admin_surface_color,
        :admin_header_color,
        :admin_workspace_color,
        :admin_sidebar_color,
        :admin_primary_color,
        :admin_ink_color,
        :logo,
        :favicon,
        :site_name,
        :admin_area_name,
        :interest_intelligence_enabled,
        :interest_intelligence_instructions,
        interest_intelligence_settings: {},
        admin_menu_section_colors: {}
      )
      normalize_interest_intelligence_params(attributes)
      normalize_admin_menu_section_colors(attributes)
      attributes
    end

    def normalize_admin_menu_section_colors(attributes)
      return unless attributes.key?(:admin_menu_section_colors)

      attributes[:admin_menu_section_colors] = LayoutSetting.normalized_admin_menu_section_styles(attributes[:admin_menu_section_colors])
    end

    def normalize_interest_intelligence_params(attributes)
      if attributes[:interest_intelligence_instructions].to_s.strip == InterestIntelligence::SystemInstructions::DEFAULT_TEXT.strip
        attributes[:interest_intelligence_instructions] = nil
      end

      raw_settings = attributes[:interest_intelligence_settings].to_h
      return if raw_settings.blank?

      defaults = InterestIntelligence::Settings::DEFAULTS
      attributes[:interest_intelligence_settings] = {
        "price_tolerance_percent" => clamp_integer(raw_settings["price_tolerance_percent"], defaults["price_tolerance_percent"], 0, 100),
        "minimum_match_score" => clamp_integer(raw_settings["minimum_match_score"], defaults["minimum_match_score"], 0, 100),
        "strong_interest_views" => clamp_integer(raw_settings["strong_interest_views"], defaults["strong_interest_views"], 1, 20),
        "max_suggestions" => clamp_integer(raw_settings["max_suggestions"], defaults["max_suggestions"], 1, 20),
        "idle_without_match_hours" => clamp_integer(raw_settings["idle_without_match_hours"], defaults["idle_without_match_hours"], 1, 720),
        "city_weight" => clamp_integer(raw_settings["city_weight"], defaults["city_weight"], 0, 100),
        "neighborhood_weight" => clamp_integer(raw_settings["neighborhood_weight"], defaults["neighborhood_weight"], 0, 100),
        "category_weight" => clamp_integer(raw_settings["category_weight"], defaults["category_weight"], 0, 100),
        "bedrooms_weight" => clamp_integer(raw_settings["bedrooms_weight"], defaults["bedrooms_weight"], 0, 100),
        "parking_weight" => clamp_integer(raw_settings["parking_weight"], defaults["parking_weight"], 0, 100),
        "price_weight" => clamp_integer(raw_settings["price_weight"], defaults["price_weight"], 0, 100),
        "broker_review_required" => ActiveModel::Type::Boolean.new.cast(raw_settings["broker_review_required"]),
        "requires_public_tracking_consent" => ActiveModel::Type::Boolean.new.cast(raw_settings["requires_public_tracking_consent"]),
        "allow_direct_lead_message" => ActiveModel::Type::Boolean.new.cast(raw_settings["allow_direct_lead_message"])
      }
    end

    def clamp_integer(value, fallback, min, max)
      number = Integer(value.presence || fallback)
      [[number, min].max, max].min
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
