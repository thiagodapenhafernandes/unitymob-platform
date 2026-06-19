class HabitationExport < ApplicationRecord
  belongs_to :admin_user
  has_one_attached :file

  STATUSES = %w[pending processing completed failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def completed?  = status == "completed"
  def failed?     = status == "failed"
  def processing? = status.in?(%w[pending processing])
  def ready?      = completed? && file.attached?
end
