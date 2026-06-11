class MetaLeadForm < ApplicationRecord
  belongs_to :meta_facebook_page

  validates :form_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :enabled, -> { where(active: true) }
end
