class HomeSetting < ApplicationRecord
  include PublicSite::BumpsPageVersion
  include TenantScoped

  SEARCH_FILTER_DISPLAY_MODES = %w[hero floating both].freeze
  SEARCH_FILTER_DISPLAY_MODE_OPTIONS = [
    ["Só filtro no hero", "hero"],
    ["Só botão flutuante", "floating"],
    ["Hero + botão flutuante", "both"]
  ].freeze
  MOBILE_SEARCH_FILTER_DISPLAY_MODES = %w[floating hero both].freeze
  MOBILE_SEARCH_FILTER_DISPLAY_MODE_OPTIONS = [
    ["Só botão flutuante", "floating"],
    ["Só filtro no hero", "hero"],
    ["Hero + botão flutuante", "both"]
  ].freeze

  # Layouts do hero: cada um é um componente de render (public_theme/components/hero_<layout>) com a identidade de cada tema.
  # "classic" é o hero de sempre (nada muda para quem não escolher outro).
  HERO_LAYOUTS = {
    "classic" => { label: "Clássico", icon: "image", description: "Título e subtítulo centralizados sobre a foto, com a busca embaixo. O hero de sempre." },
    "bar" => { label: "Barra", icon: "distribute-horizontal", description: "Título grande e uma barra de busca em linha, com Comprar/Alugar, localização, tipo e quartos." },
    "card" => { label: "Cartão", icon: "layout-sidebar-inset", description: "Um cartão de busca sobre a foto, com abas, filtros, atalhos e (opcional) busca por descrição com IA e voz." }
  }.freeze
  HERO_LAYOUT_OPTIONS = HERO_LAYOUTS.map { |key, meta| [meta[:label], key] }.freeze
  HERO_SEARCH_ALIGN_OPTIONS = [["Esquerda", "left"], ["Centro", "center"], ["Direita", "right"]].freeze
  HERO_AI_SUGGESTION_LIMIT = 3

  HEADER_COLOR_FIELDS = {
    header_menu_color: "Texto e ícones",
    header_menu_hover_color: "Texto e ícones — hover e foco",
    header_cta_background: "Botão Fale Conosco — fundo",
    header_cta_hover_background: "Botão Fale Conosco — fundo no hover"
  }.freeze
  store_accessor :header_colors, *HEADER_COLOR_FIELDS.keys
  validates(*HEADER_COLOR_FIELDS.keys, format: { with: /\A#[0-9a-f]{6}(?:[0-9a-f]{2})?\z/i }, allow_blank: true)

  # ActiveStorage attachments
  has_one_attached :hero_background_desktop
  has_one_attached :hero_background_mobile
  has_one_attached :filter_panel_background
  # Foto lateral do menu em tela cheia (navigation-overlay). Sem ela, o menu usa a do hero.
  has_one_attached :navigation_menu_image
  NAVIGATION_MENU_IMAGE_TYPES = %w[image/png image/jpeg image/webp].freeze
  NAVIGATION_MENU_IMAGE_MAX_BYTES = 8.megabytes
  attribute :remove_navigation_menu_image, :boolean, default: false
  after_save :purge_navigation_menu_image, if: :remove_navigation_menu_image
  has_many :hero_slides, -> { ordered }, class_name: "HomeHeroSlide", dependent: :destroy
  accepts_nested_attributes_for :hero_slides, allow_destroy: true
  
  # Validations
  validates :hero_layout, inclusion: { in: HERO_LAYOUTS.keys }
  validates :hero_search_align, inclusion: { in: HERO_SEARCH_ALIGN_OPTIONS.map(&:last) }
  validates :hero_ai_suggestions, length: { maximum: 600 }
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
  validates :search_filter_display_mode, inclusion: { in: SEARCH_FILTER_DISPLAY_MODES }
  validates :mobile_search_filter_display_mode, inclusion: { in: MOBILE_SEARCH_FILTER_DISPLAY_MODES }
  validates :public_header_css, length: { maximum: 2000 }, allow_blank: true
  validates :header_cta_label, length: { maximum: 30 }
  validates :header_cta_url, format: { with: PublicHeaderMenu::URL_FORMAT, message: "deve começar com /, http(s):// ou #modal-..." }, allow_blank: true
  validate :public_header_css_must_be_declarations_only
  validate :navigation_menu_image_must_be_web_image
  
  # Singleton pattern - só existe um registro
  def self.instance(tenant: Current.tenant || Tenant.public_for)
    raise ArgumentError, "Tenant obrigatório para configurações da home" if tenant.blank?

    where(tenant: tenant).first_or_create!(
      hero_title: "Encontre o imóvel ideal com a #{tenant.name}.",
      hero_subtitle: "Compra, locação e oportunidades imobiliárias em um só lugar.",
      cta_title: "Pronto para encontrar seu imóvel?",
      cta_subtitle: "Entre em contato e descubra as melhores oportunidades para o seu momento.",
      services_active: true,
      why_choose_active: true,
      cta_contact_active: true,
      overlay_opacity: 0.7,  # Opacidade padrão do overlay no hero
      hero_button_color: '#BFAB25', # Default brand accent
      hero_button_text_color: '#FFFFFF', # Default white text
      search_filter_background_color: '#FFFFFF',
      search_filter_background_opacity: 0.25, # Padrão = preset Vidro (translúcido sobre a foto)
      search_filter_border_enabled: true,
      search_filter_border_color: '#FFFFFF',
      search_filter_border_opacity: 0.45,
      search_filter_text_color: '#022B3A',
      search_filter_field_background_color: '#FFFFFF',
      search_filter_field_background_opacity: 0.25,
      search_filter_backdrop_blur: 16,
      search_filter_border_radius: 35,
      hero_title_font_size: 72,
      hero_subtitle_font_size: 20,
      search_filter_display_mode: "hero",
      mobile_search_filter_display_mode: "hero",
      public_header_css: nil
    )
  end

  def hero_layout_classic? = hero_layout == "classic"

  # Frases de exemplo do modo "Descreva seu imóvel" (uma por linha, até 3).
  def hero_ai_suggestion_list
    hero_ai_suggestions.to_s.lines.map { |line| line.squish.first(120) }.compact_blank.first(HERO_AI_SUGGESTION_LIMIT)
  end

  # Busca por voz/descrição no hero (qualquer layout): ligada aqui E com a IA de busca da conta pronta (chave + recurso ativo).
  def hero_ai_search_available?
    hero_ai_search_enabled? && Ai::PropertySearch::PublicQuery.available?(tenant: tenant)
  end

  def search_filter_in_hero?
    search_filter_display_mode != "floating"
  end

  def mobile_search_filter_in_hero?
    mobile_search_filter_display_mode.in?(%w[hero both])
  end

  def floating_search_filter?
    search_filter_display_mode.in?(%w[floating both])
  end

  def mobile_floating_search_filter?
    mobile_search_filter_display_mode.in?(%w[floating both])
  end

  def renders_hero_search_filter?
    search_filter_in_hero? || mobile_search_filter_in_hero?
  end

  def renders_floating_search_filter?
    floating_search_filter? || mobile_floating_search_filter?
  end

  def hero_search_filter_visibility_class
    return nil if search_filter_in_hero? && mobile_search_filter_in_hero?
    return "public-hero-search--desktop-only" if search_filter_in_hero?
    return "public-hero-search--mobile-only" if mobile_search_filter_in_hero?

    nil
  end

  def floating_search_filter_visibility_class
    return nil if floating_search_filter? && mobile_floating_search_filter?
    return "public-global-search--desktop-only" if floating_search_filter?
    return "public-global-search--mobile-only" if mobile_floating_search_filter?

    nil
  end

  # Filtros próprios da listagem (barra, gaveta e botão "Filtros") só onde o
  # filtro global não aparece — senão a busca fica duplicada. Espelha
  # floating_search_filter_visibility_class para a mesma faixa de tela.
  def listing_filters_visibility_class
    return "public-listing-filters--hidden" if floating_search_filter? && mobile_floating_search_filter?
    return "public-listing-filters--mobile-only" if floating_search_filter?
    return "public-listing-filters--desktop-only" if mobile_floating_search_filter?

    nil
  end

  def public_header_style
    public_header_css.to_s.strip.presence
  end

  def search_filter_background_rgba
    color_with_alpha(search_filter_background_color.presence || '#FFFFFF', search_filter_background_opacity.presence || 0.25)
  end

  def search_filter_field_background_rgba
    color_with_alpha(search_filter_field_background_color.presence || '#FFFFFF', search_filter_field_background_opacity.presence || 0.25)
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
    (search_filter_border_radius.presence || 35).to_i.clamp(0, 40)
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

  def navigation_menu_image_must_be_web_image
    change = attachment_changes["navigation_menu_image"]
    return unless change.is_a?(ActiveStorage::Attached::Changes::CreateOne)

    blob = change.blob
    return if NAVIGATION_MENU_IMAGE_TYPES.include?(blob.content_type) && blob.byte_size <= NAVIGATION_MENU_IMAGE_MAX_BYTES

    errors.add(:navigation_menu_image, "deve ser PNG, JPEG ou WebP de até 8 MB")
  end

  # Remoção explícita no admin: volta a valer a foto do hero. Envio de nova foto
  # no mesmo salvamento tem prioridade.
  def purge_navigation_menu_image
    self.remove_navigation_menu_image = false
    return if attachment_changes["navigation_menu_image"].present?

    navigation_menu_image.purge_later if navigation_menu_image.attached?
  end

  def public_header_css_must_be_declarations_only
    return if public_header_css.blank?

    if public_header_css.match?(/[{}<>]/)
      errors.add(:public_header_css, "deve conter apenas declarações CSS, sem seletores ou tags")
    end
  end
end
