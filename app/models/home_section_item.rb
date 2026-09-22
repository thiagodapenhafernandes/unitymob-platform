class HomeSectionItem < ApplicationRecord
  include TenantScoped
  # Associations
  belongs_to :home_section, touch: true
  before_validation { self.tenant = home_section&.tenant if home_section }
  
  # ActiveStorage
  has_one_attached :icon
  has_one_attached :video_file
  
  # Validations
  validates :title, presence: true
  
  # Scopes
  scope :active, -> { where(active: true).order(:display_order) }
  scope :ordered, -> { order(:display_order, :created_at) }
  scope :video_items, -> { where(source_type: %w[external upload]) }

  after_commit :clear_home_cache

  def badges_text
    Array(badges).compact_blank.join(", ")
  end

  def badges_text=(value)
    self.badges = value.to_s.split(",").map(&:strip).compact_blank.first(4)
  end

  def video_item?
    source_type.in?(%w[external upload])
  end

  private

  def clear_home_cache
    return if tenant_id.blank?

    Rails.cache.delete("home_sections_active_v3:tenant:#{tenant_id}")
    Rails.cache.delete("home_sections_active_v2:tenant:#{tenant_id}")
    Rails.cache.delete_matched("public_home/tenant/*") if Rails.cache.respond_to?(:delete_matched)
    Rails.cache.delete_matched("views/*") if Rails.cache.respond_to?(:delete_matched)
  rescue NotImplementedError
    Rails.cache.clear
  end
end
