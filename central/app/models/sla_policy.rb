class SlaPolicy < ActiveRecord::Base
  validates :priority, inclusion: { in: Support::Ticket::PRIORITIES }, uniqueness: true
  validates :first_response_minutes, :resolution_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 525600 }, allow_nil: true
end
