class MetaLeadForm < ApplicationRecord
  belongs_to :meta_facebook_page

  validates :form_id, presence: true, uniqueness: { scope: :meta_facebook_page_id }
  validates :name, presence: true

  scope :enabled, -> { where(active: true) }
end
