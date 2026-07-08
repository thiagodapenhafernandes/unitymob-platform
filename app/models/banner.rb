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

  # Sem callback de cache: banners são renderizados ao vivo via display_banner
  # (consulta o banco a cada render, fora dos fragments cacheados da home).
  # O antigo delete_matched("views/*") varria o keyspace inteiro do Redis a
  # cada save e apagava fragments de todos os tenants sem necessidade.

  def displayable?
    image_desktop.attached? || image_mobile.attached? || title.present? || description.present?
  end
end
