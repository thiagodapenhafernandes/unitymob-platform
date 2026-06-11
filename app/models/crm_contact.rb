class CrmContact < ApplicationRecord
  belongs_to :vista_import_batch, optional: true

  has_many :client_interactions, dependent: :nullify
  has_many :habitation_interactions, dependent: :nullify
  has_many :crm_appointments, dependent: :nullify
  has_many :client_property_interests, dependent: :nullify

  validates :vista_code, presence: true, uniqueness: true
  validates :name, presence: true
end
