class Banner < ApplicationRecord
  # ActiveStorage attachments
  has_one_attached :image_desktop
  has_one_attached :image_mobile
  
  # Positions as array (can be in multiple places)
  POSITIONS = {
    'home_after_hero' => 'Início - Após Hero',
    'search_results' => 'Resultados de Busca',
    'property_detail' => 'Detalhes do Imóvel',
    'home_before_footer' => 'Início - Antes do Rodapé',
    'sidebar' => 'Barra Lateral'
  }.freeze
  
  # Validations
  validates :title, presence: true
  validates :link_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true
  validates :positions, presence: true
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_position, ->(pos) { where("? = ANY(positions)", pos).order(:display_order) }
  scope :ordered, -> { order(:display_order, :created_at) }

  after_commit :clear_banner_cache

  def displayable?
    image_desktop.attached? || image_mobile.attached? || title.present? || description.present?
  end

  private

  def clear_banner_cache
    Rails.cache.delete_matched("views/*") if Rails.cache.respond_to?(:delete_matched)
    Rails.cache.delete("home_sections_active_v2")
  rescue NotImplementedError
    Rails.cache.clear
  end
end
