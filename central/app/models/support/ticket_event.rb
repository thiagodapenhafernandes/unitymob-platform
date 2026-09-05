class Support::TicketEvent < ActiveRecord::Base
  self.table_name = "support_ticket_events"
  belongs_to :ticket, class_name: 'Support::Ticket'
  belongs_to :staff, optional: true
  def readonly? = persisted?
end
