class SystemHealthSnapshot < ApplicationRecord
  RETENTION_PERIOD = 90.days

  belongs_to :tenant, optional: true

  validates :status, inclusion: { in: %w[healthy warning critical unknown] }
  validates :source, :collected_at, presence: true

  scope :recent_first, -> { order(collected_at: :desc) }
  scope :platform, -> { where(tenant_id: nil) }
end
