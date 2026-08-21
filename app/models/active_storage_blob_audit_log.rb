class ActiveStorageBlobAuditLog < ApplicationRecord
  ACTIONS = %w[
    purge_requested
    purge_started
    purge_missing_deleted
    purge_scheduled
    missing_variant_cleaned
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :source, presence: true

  self.record_timestamps = false

  before_create :set_created_at

  scope :recent, -> { order(created_at: :desc) }

  def readonly?
    persisted?
  end

  private

  def set_created_at
    self.created_at ||= Time.current
  end
end
