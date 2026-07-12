class HomeSectionItem < ApplicationRecord
  include TenantScoped
  # Associations
  belongs_to :home_section
  before_validation { self.tenant = home_section&.tenant if home_section }
  
  # ActiveStorage
  has_one_attached :icon
  
  # Validations
  validates :title, presence: true
  
  # Scopes
  scope :active, -> { where(active: true).order(:display_order) }
  scope :ordered, -> { order(:display_order, :created_at) }
end
