class HomeSectionItem < ApplicationRecord
  include TenantScoped
  VIDEO_CONTENT_TYPES = %w[video/mp4 video/quicktime video/webm video/ogg video/3gpp].freeze
  VIDEO_MAX_BYTES = 200.megabytes

  # Associations
  belongs_to :home_section, touch: true
  before_validation { self.tenant = home_section&.tenant if home_section }
  
  # ActiveStorage
  has_one_attached :icon
  has_one_attached :video_file
  
  # Validations
  validates :title, presence: true
  validate :video_file_is_supported
  
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

  def video_file_is_supported
    return unless video_file.attached?

    unless VIDEO_CONTENT_TYPES.include?(video_file.blob.content_type.to_s)
      errors.add(:video_file, "deve ser um vídeo MP4, MOV, WebM, OGG ou 3GP")
    end

    if video_file.blob.byte_size.to_i > VIDEO_MAX_BYTES
      errors.add(:video_file, "deve ter no máximo 200 MB")
    end
  end

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
