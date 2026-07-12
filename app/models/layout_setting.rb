class LayoutSetting < ApplicationRecord
  include TenantScoped
  has_one_attached :logo
  has_one_attached :favicon


  # Cor primária padrão da plataforma interna. O cinza-neutro é a base; esta cor é só o destaque.
  ADMIN_SURFACE_DEFAULT = '#FFFFFF'.freeze
  ADMIN_HEADER_DEFAULT = '#EEF2F7'.freeze
  ADMIN_WORKSPACE_DEFAULT = '#EEF2F7'.freeze
  ADMIN_SIDEBAR_DEFAULT = '#FFFFFF'.freeze
  ADMIN_PRIMARY_DEFAULT = '#365F8F'.freeze
  ADMIN_INK_DEFAULT = '#1F2733'.freeze
  ADMIN_THEME_MODE_DEFAULT = 'light'.freeze
  ADMIN_THEME_MODES = %w[light dark].freeze
  ADMIN_DARK_THEME = {
    surface: '#172033',
    header: '#202B3D',
    workspace: '#0F1726',
    sidebar: '#141D2D',
    ink: '#E6EDF7'
  }.freeze
  ADMIN_AREA_NAME_DEFAULT = 'Plataforma'.freeze
  LEGACY_ADMIN_PRIMARY_DEFAULT = '#2563EB'.freeze
  ADMIN_MENU_SECTION_SHADOW_DEFAULT = "inset 2px 0 0 #365F8F".freeze
  ADMIN_MENU_SECTION_SHADOW_PATTERN = /\A(?:inset\s+)?(?:0|-?\d+(?:\.\d+)?px)\s+(?:0|-?\d+(?:\.\d+)?px)(?:\s+(?:0|\d+(?:\.\d+)?px)){0,2}\s+#[0-9a-fA-F]{6}\z/.freeze
  ADMIN_MENU_SECTION_STYLE_DEFAULTS = {
    "product" => { "background_color" => "#E8F0FB", "background_opacity" => 100, "text_color" => "#245486", "border_color" => "#C7D8EE", "box_shadow" => "inset 2px 0 0 #365F8F" },
    "operation" => { "background_color" => "#EBFFFE", "background_opacity" => 100, "text_color" => "#0F766E", "border_color" => "#C9EEEB", "box_shadow" => "inset 2px 0 0 #0F766E" },
    "management" => { "background_color" => "#ECE0FF", "background_opacity" => 100, "text_color" => "#7C3AED", "border_color" => "#D2C0F2", "box_shadow" => "inset 2px 0 0 #365F8F" },
    "growth" => { "background_color" => "#DB2777", "background_opacity" => 10, "text_color" => "#DB2777", "border_color" => "#ECC1D4", "box_shadow" => "inset 2px 0 0 #365F8F" },
    "public_site" => { "background_color" => "#0891B2", "background_opacity" => 10, "text_color" => "#0891B2", "border_color" => "#BDDDE5", "box_shadow" => "inset 2px 0 0 #365F8F" },
    "integrations" => { "background_color" => "#D97706", "background_opacity" => 10, "text_color" => "#D97706", "border_color" => "#E2D0BB", "box_shadow" => "inset 2px 0 0 #365F8F" },
    "settings" => { "background_color" => "#64748B", "background_opacity" => 10, "text_color" => "#64748B", "border_color" => "#AFC3DE", "box_shadow" => "inset 2px 0 0 #365F8F" },
    "account" => { "background_color" => "#475569", "background_opacity" => 10, "text_color" => "#475569", "border_color" => "#B0C1D8", "box_shadow" => "inset 2px 0 0 #365F8F" }
  }.transform_values(&:freeze).freeze

  validates :primary_color, presence: true
  validates :secondary_color, presence: true
  validates :accent_color, presence: true
  validates :admin_theme_mode, inclusion: { in: ADMIN_THEME_MODES }, if: -> { has_attribute?(:admin_theme_mode) }

  def admin_dark_mode?
    has_attribute?(:admin_theme_mode) && admin_theme_mode == 'dark'
  end

  def effective_admin_theme
    return ADMIN_DARK_THEME.merge(primary: admin_primary_color.presence || ADMIN_PRIMARY_DEFAULT) if admin_dark_mode?

    {
      surface: admin_surface_color.presence || ADMIN_SURFACE_DEFAULT,
      header: admin_header_color.presence || ADMIN_HEADER_DEFAULT,
      workspace: admin_workspace_color.presence || ADMIN_WORKSPACE_DEFAULT,
      sidebar: admin_sidebar_color.presence || ADMIN_SIDEBAR_DEFAULT,
      primary: admin_primary_color.presence || ADMIN_PRIMARY_DEFAULT,
      ink: admin_ink_color.presence || ADMIN_INK_DEFAULT
    }
  end

  def admin_area_label
    return ADMIN_AREA_NAME_DEFAULT unless has_attribute?(:admin_area_name)

    admin_area_name.presence || ADMIN_AREA_NAME_DEFAULT
  end

  def self.instance(tenant: Current.tenant || Tenant.public_for)
    raise ArgumentError, "Tenant obrigatório para configurações de layout" if tenant.blank?
    defaults = {
      primary_color: '#022B3A',
      secondary_color: '#053C5E',
      accent_color: '#BFAB25',
      admin_primary_color: ADMIN_PRIMARY_DEFAULT,
      site_name: 'Salute Imóveis'
    }
    defaults[:admin_area_name] = ADMIN_AREA_NAME_DEFAULT if column_names.include?('admin_area_name')
    defaults[:admin_surface_color] = ADMIN_SURFACE_DEFAULT if column_names.include?('admin_surface_color')
    defaults[:admin_header_color] = ADMIN_HEADER_DEFAULT if column_names.include?('admin_header_color')
    defaults[:admin_workspace_color] = ADMIN_WORKSPACE_DEFAULT if column_names.include?('admin_workspace_color')
    defaults[:admin_sidebar_color] = ADMIN_SIDEBAR_DEFAULT if column_names.include?('admin_sidebar_color')
    defaults[:admin_ink_color] = ADMIN_INK_DEFAULT if column_names.include?('admin_ink_color')
    defaults[:admin_theme_mode] = ADMIN_THEME_MODE_DEFAULT if column_names.include?('admin_theme_mode')
    defaults[:admin_menu_section_colors] = ADMIN_MENU_SECTION_STYLE_DEFAULTS if column_names.include?('admin_menu_section_colors')
    defaults[:interest_intelligence_enabled] = true if column_names.include?('interest_intelligence_enabled')
    defaults[:interest_intelligence_settings] = InterestIntelligence::Settings::DEFAULTS if column_names.include?('interest_intelligence_settings')

    setting = where(tenant: tenant).first_or_initialize(defaults.merge(tenant: tenant))

    # Se já existir mas algum campo estiver nulo (como o accent_color do erro)
    if setting.persisted?
      setting.accent_color ||= '#BFAB25'
      setting.primary_color ||= '#022B3A'
      setting.secondary_color ||= '#053C5E'
      setting.admin_area_name ||= ADMIN_AREA_NAME_DEFAULT if setting.has_attribute?(:admin_area_name)
      setting.admin_surface_color ||= ADMIN_SURFACE_DEFAULT if setting.has_attribute?(:admin_surface_color)
      setting.admin_header_color ||= ADMIN_HEADER_DEFAULT if setting.has_attribute?(:admin_header_color)
      setting.admin_workspace_color ||= ADMIN_WORKSPACE_DEFAULT if setting.has_attribute?(:admin_workspace_color)
      setting.admin_sidebar_color ||= ADMIN_SIDEBAR_DEFAULT if setting.has_attribute?(:admin_sidebar_color)
      setting.admin_ink_color ||= ADMIN_INK_DEFAULT if setting.has_attribute?(:admin_ink_color)
      setting.admin_theme_mode ||= ADMIN_THEME_MODE_DEFAULT if setting.has_attribute?(:admin_theme_mode)
      if setting.has_attribute?(:admin_menu_section_colors)
        setting[:admin_menu_section_colors] = normalized_admin_menu_section_styles(setting[:admin_menu_section_colors])
      end
      setting.interest_intelligence_settings = InterestIntelligence::Settings::DEFAULTS.merge(setting.interest_intelligence_settings.to_h) if setting.has_attribute?(:interest_intelligence_settings)
      if setting.admin_primary_color.blank? || setting.admin_primary_color.casecmp?(LEGACY_ADMIN_PRIMARY_DEFAULT)
        setting.admin_primary_color = ADMIN_PRIMARY_DEFAULT
      end
      setting.save if setting.changed?
    else
      setting.save!
    end

    setting
  end

  def interest_intelligence_effective_instructions
    InterestIntelligence::SystemInstructions.effective_text(self)
  end

  def admin_menu_section_styles
    return ADMIN_MENU_SECTION_STYLE_DEFAULTS unless has_attribute?(:admin_menu_section_colors)

    self.class.normalized_admin_menu_section_styles(self[:admin_menu_section_colors])
  end

  def self.normalized_admin_menu_section_styles(raw_styles)
    raw_styles = raw_styles.to_h.stringify_keys

    ADMIN_MENU_SECTION_STYLE_DEFAULTS.each_with_object({}) do |(key, defaults), normalized|
      raw_section = raw_styles[key]
      legacy_color = raw_section if raw_section.is_a?(String)
      section = raw_section.respond_to?(:to_h) ? raw_section.to_h.stringify_keys : {}

      normalized[key] = {
        "background_color" => normalized_hex(section["background_color"] || legacy_color, defaults["background_color"]),
        "background_opacity" => normalized_opacity(section["background_opacity"], defaults["background_opacity"]),
        "text_color" => normalized_hex(section["text_color"] || legacy_color, defaults["text_color"]),
        "border_color" => normalized_hex(section["border_color"] || legacy_color, defaults["border_color"]),
        "box_shadow" => normalized_box_shadow(section["box_shadow"], defaults["box_shadow"])
      }
    end
  end

  def self.normalized_hex(value, fallback)
    candidate = value.to_s.strip
    candidate.match?(/\A#[0-9a-fA-F]{6}\z/) ? candidate.upcase : fallback
  end

  def self.normalized_opacity(value, fallback)
    number = Integer(value.presence || fallback)
    [[number, 0].max, 100].min
  rescue ArgumentError, TypeError
    fallback
  end

  def self.normalized_box_shadow(value, fallback = ADMIN_MENU_SECTION_SHADOW_DEFAULT)
    candidate = value.to_s.squish
    candidate.match?(ADMIN_MENU_SECTION_SHADOW_PATTERN) ? candidate : fallback
  end
end
