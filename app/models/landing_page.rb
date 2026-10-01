class LandingPage < ApplicationRecord
  include PublicSite::BumpsPageVersion
  include TenantScoped
  include PublicRootSlug
  # Só "published" está no ar (active é derivado do status).
  include PublishableStatus
  # O campo de URL vem "" quando fica em branco; o FriendlyId só gera o slug a partir de nil.
  before_validation { self.slug = nil if slug.blank? }
  extend FriendlyId
  friendly_id :title, use: :slugged

  has_many :blocks, -> { order(:position, :id) }, class_name: "LandingPageBlock", dependent: :destroy, inverse_of: :landing_page
  accepts_nested_attributes_for :blocks, allow_destroy: true, reject_if: ->(attrs) { attrs["block_type"].blank? && attrs["id"].blank? }

  validates :title, presence: true
  validates :layout_columns, inclusion: { in: 1..3 }
  validate :single_interactive_showcase
  validates :slug, presence: true, uniqueness: { scope: :tenant_id }

  # Ensure filter_params is always a hash
  after_initialize :set_default_filter_params, if: :new_record?

  scope :active, -> { where(active: true) }

  # Multiselects gravam [""]; limpar na entrada mantém filter_params só com o que foi escolhido.
  before_validation :compact_filter_params

  # Página montada por blocos (as antigas sem bloco seguem na tela legada até serem convertidas).
  def blocks?
    blocks.any?
  end

  def visible_blocks
    blocks.select(&:visible?)
  end

  private

  # A vitrine com filtros do visitante e paginação usa `?page=`: só pode haver uma por página.
  def single_interactive_showcase
    interactive = blocks.reject(&:marked_for_destruction?).count(&:interactive_showcase?)
    errors.add(:base, "Só uma vitrine por página pode ter filtros do visitante e paginação. Desligue em uma delas.") if interactive > 1
  end

  def compact_filter_params
    self.filter_params = (filter_params || {}).to_h.transform_values { |value| value.is_a?(Array) ? value.compact_blank : value }
  end

  def set_default_filter_params
    self.filter_params ||= {}
  end
end
