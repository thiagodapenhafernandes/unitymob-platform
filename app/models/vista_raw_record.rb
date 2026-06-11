class VistaRawRecord < ApplicationRecord
  belongs_to :vista_import_batch
  has_many :vista_file_assets, dependent: :nullify

  validates :table_name, presence: true
  validates :row_index, presence: true
  validates :payload, presence: true
end
