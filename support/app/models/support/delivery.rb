class Support::Delivery < ActiveRecord::Base
  self.table_name = "support_deliveries"
  belongs_to :account, class_name: "Support::Account"
  belongs_to :ticket, class_name: "Support::Ticket", optional: true
  scope :due, -> { where(delivered_at: nil, failed_at: nil).where("next_attempt_at <= ?", Time.current) }
  before_validation { self.uid ||= SecureRandom.uuid; self.next_attempt_at ||= Time.current }
end
