class MetaFacebookPage < ApplicationRecord
  belongs_to :user_meta_integration
  has_many :meta_lead_forms, dependent: :destroy

  validates :page_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :enabled, -> { where(active: true) }
end
