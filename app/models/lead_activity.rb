class LeadActivity < ApplicationRecord
  belongs_to :lead
  
  validates :kind, presence: true

  # kinds: created, distributed, accepted, rejected, comment, status_change
end
