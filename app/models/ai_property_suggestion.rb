class AiPropertySuggestion < ApplicationRecord
  belongs_to :habitation
  belongs_to :admin_user, optional: true

  STATUSES = %w[pending applied failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :latest_first, -> { order(created_at: :desc) }

  def seo_keywords_list
    generated_seo_keywords.to_s
      .split(/[,;\n]/)
      .map(&:strip)
      .reject(&:blank?)
      .uniq
  end
end
