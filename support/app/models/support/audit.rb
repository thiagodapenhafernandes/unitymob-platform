class Support::Audit < ActiveRecord::Base
  self.table_name = "support_audits"
  def readonly? = persisted?

  after_create do
    next if SupportDesk.central? || !ticket_id || !action.start_with?("access_", "assisted_")
    next if action == "assisted_request" && details["method"] == "GET" && details["action"] != "attend"
    ticket = Support::Ticket.find(ticket_id)
    Support::Delivery.create!(account_id: account_id, payload: { kind: "access_audit", ticket_uid: ticket.uid, audit: attributes.slice("actor", "action", "details") })
  end
end
