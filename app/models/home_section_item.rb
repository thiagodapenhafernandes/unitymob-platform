class HomeSectionItem < ApplicationRecord
  # Associations
  belongs_to :home_section
  
  # ActiveStorage
  has_one_attached :icon
  
  # Validations
  validates :title, presence: true
  
  # Scopes
  scope :active, -> { where(active: true).order(:display_order) }
  scope :ordered, -> { order(:display_order, :created_at) }
end
