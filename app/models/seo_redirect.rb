class SeoRedirect < ApplicationRecord
  VALID_STATUS_CODES = [301, 302, 307, 308].freeze

  belongs_to :created_by_admin_user, class_name: "AdminUser", optional: true

  validates :from_path, :to_path, presence: true
  validates :from_path, uniqueness: true
  validates :status_code, inclusion: { in: VALID_STATUS_CODES }
  validate :paths_are_different

  before_validation :normalize_paths

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(updated_at: :desc) }

  def register_hit!
    increment!(:hit_count)
    update_column(:last_hit_at, Time.current)
  end

  private

  def normalize_paths
    self.from_path = normalize_path(from_path)
    self.to_path = normalize_path(to_path)
  end

  def normalize_path(value)
    value = value.to_s.strip
    return if value.blank?
    return value if value.start_with?("http://", "https://")

    value.start_with?("/") ? value : "/#{value}"
  end

  def paths_are_different
    errors.add(:to_path, "deve ser diferente da origem") if from_path.present? && from_path == to_path
  end
end
