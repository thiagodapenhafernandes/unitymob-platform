class VistaImportBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  has_many :vista_raw_records, dependent: :destroy
  has_many :vista_file_assets, dependent: :destroy

  validates :dump_dir, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
