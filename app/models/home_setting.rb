class HomeSetting < ApplicationRecord
  include TenantScoped
  # ActiveStorage attachments
  has_one_attached :hero_background_desktop
  has_one_attached :hero_background_mobile
  has_many :hero_slides, -> { ordered }, class_name: "HomeHeroSlide", dependent: :destroy
  accepts_nested_attributes_for :hero_slides, allow_destroy: true
  
  # Validations
  validates :hero_title, presence: true
  validates :hero_subtitle, presence: true
  validates :search_filter_background_color,
            :search_filter_border_color,
            :search_filter_text_color,
            :search_filter_field_background_color,
            format: { with: /\A#[0-9a-f]{6}\z/i, allow_blank: true }
  validates :search_filter_background_opacity,
            :search_filter_border_opacity,
            :search_filter_field_background_opacity,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1, allow_blank: true }
  validates :search_filter_backdrop_blur,
            :search_filter_border_radius,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 40, allow_blank: true }
  validates :hero_title_font_size,
            numericality: { only_integer: true, greater_than_or_equal_to: 24, less_than_or_equal_to: 96, allow_blank: true }
  validates :hero_subtitle_font_size,
            numericality: { only_integer: true, greater_than_or_equal_to: 12, less_than_or_equal_to: 36, allow_blank: true }
  
  # Singleton pattern - só existe um registro
  def self.instance(tenant: Current.tenant || Tenant.public_for)
    raise ArgumentError, "Tenant obrigatório para configurações da home" if tenant.blank?

    where(tenant: tenant).first_or_create!(
      hero_title: "Compre ou alugue na imobiliária mais amada de Balneário Camboriú.",
      hero_subtitle: "Aqui o lar é o centro das grandes histórias da vida.",
      cta_title: "Pronto para Encontrar Seu Imóvel?",
      cta_subtitle: "Entre em contato conosco e descubra as melhores oportunidades do mercado.",
      services_active: true,
      why_choose_active: true,
      cta_contact_active: true,
      overlay_opacity: 0.7,  # Opacidade padrão do overlay no hero
      hero_button_color: '#BFAB25', # Default brand accent
      hero_button_text_color: '#FFFFFF', # Default white text
      search_filter_background_color: '#FFFFFF',
      search_filter_background_opacity: 0.9,
      search_filter_border_enabled: true,
      search_filter_border_color: '#FFFFFF',
      search_filter_border_opacity: 0.45,
      search_filter_text_color: '#022B3A',
      search_filter_field_background_color: '#FFFFFF',
      search_filter_field_background_opacity: 0.85,
      search_filter_backdrop_blur: 16,
      search_filter_border_radius: 22,
      hero_title_font_size: 72,
      hero_subtitle_font_size: 20
    )
  end

  def search_filter_background_rgba
    color_with_alpha(search_filter_background_color.presence || '#FFFFFF', search_filter_background_opacity.presence || 0.9)
  end

  def search_filter_field_background_rgba
    color_with_alpha(search_filter_field_background_color.presence || '#FFFFFF', search_filter_field_background_opacity.presence || 0.85)
  end

  def search_filter_border_color_value
    color_with_alpha(search_filter_border_color.presence || '#FFFFFF', search_filter_border_opacity.presence || 0.45)
  end

  def search_filter_border_style
    ActiveModel::Type::Boolean.new.cast(search_filter_border_enabled) ? "1px solid #{search_filter_border_color_value}" : "0 solid transparent"
  end

  def search_filter_text_color_value
    search_filter_text_color.presence || '#022B3A'
  end

  def search_filter_backdrop_blur_value
    (search_filter_backdrop_blur.presence || 16).to_i.clamp(0, 40)
  end

  def search_filter_border_radius_value
    (search_filter_border_radius.presence || 22).to_i.clamp(0, 40)
  end

  def active_hero_slides
    hero_slides.active.ordered
  end

  def hero_title_font_size_value
    (hero_title_font_size.presence || 72).to_i.clamp(24, 96)
  end

  def hero_subtitle_font_size_value
    (hero_subtitle_font_size.presence || 20).to_i.clamp(12, 36)
  end

  private

  def color_with_alpha(color, alpha)
    hex = color.to_s.strip
    opacity = alpha.to_f.clamp(0, 1)

    return "rgba(255, 255, 255, #{opacity})" unless hex.match?(/\A#[0-9a-f]{6}\z/i)

    red = hex[1..2].to_i(16)
    green = hex[3..4].to_i(16)
    blue = hex[5..6].to_i(16)

    "rgba(#{red}, #{green}, #{blue}, #{opacity})"
  end
end
