class VistaFileAsset < ApplicationRecord
  STATUSES = %w[pending downloaded failed skipped].freeze
  KINDS = %w[property_photo property_document client_document agent_document other].freeze

  belongs_to :vista_import_batch
  belongs_to :vista_raw_record, optional: true
  belongs_to :habitation, optional: true
  belongs_to :active_storage_attachment, class_name: "ActiveStorage::Attachment", optional: true

  validates :table_name, :kind, :source_path, :filename, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }

  scope :pending, -> { where(status: "pending") }
  scope :downloaded, -> { where(status: "downloaded") }
  scope :failed, -> { where(status: "failed") }
end
