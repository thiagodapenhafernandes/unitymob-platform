class LandingPage < ApplicationRecord
  include TenantScoped
  include PublicRootSlug
  extend FriendlyId
  friendly_id :title, use: :slugged

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :tenant_id }

  # Ensure filter_params is always a hash
  after_initialize :set_default_filter_params, if: :new_record?

  scope :active, -> { where(active: true) }

  # Multiselects gravam [""]; limpar na entrada mantém filter_params só com o que foi escolhido.
  before_validation :compact_filter_params

  private

  def compact_filter_params
    self.filter_params = (filter_params || {}).to_h.transform_values { |value| value.is_a?(Array) ? value.compact_blank : value }
  end

  def set_default_filter_params
    self.filter_params ||= {}
  end
end
