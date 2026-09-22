class Banner < ApplicationRecord
  include TenantScoped
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
  
  # Dica por posição no formulário: ícone, tom, tamanho recomendado (o site redimensiona até 1440x360 / 768x360) e onde aparece.
  POSITION_META = {
    'home_after_hero' => { icon: 'layout-text-window-reverse', tone: 'blue', size: '1440 × 360', note: 'Faixa larga logo abaixo do topo da Home' },
    'search_results' => { icon: 'search', tone: 'teal', size: '1440 × 360', note: 'Acima da lista de imóveis na busca' },
    'property_detail' => { icon: 'house-door', tone: 'violet', size: '1440 × 360', note: 'Largura total na página do imóvel' },
    'home_before_footer' => { icon: 'layout-text-window', tone: 'amber', size: '1440 × 360', note: 'Fim da Home, antes do rodapé' },
    'sidebar' => { icon: 'layout-sidebar-inset-reverse', tone: 'pink', size: '768 × 360', note: 'Coluna lateral do imóvel; usa a imagem mobile' }
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
