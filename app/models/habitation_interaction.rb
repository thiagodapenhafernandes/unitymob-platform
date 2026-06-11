class HabitationInteraction < ApplicationRecord
  belongs_to :vista_import_batch, optional: true
  belongs_to :habitation, optional: true
  belongs_to :crm_contact, optional: true
  belongs_to :proprietor, optional: true
  belongs_to :admin_user, optional: true

  validates :source_table, :source_key, presence: true
end
