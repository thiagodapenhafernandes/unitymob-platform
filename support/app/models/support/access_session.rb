class Support::AccessSession < ActiveRecord::Base
  self.table_name = "support_access_sessions"
  belongs_to :account, class_name: "Support::Account"
  belongs_to :ticket, class_name: "Support::Ticket"
  def live? = account.active? && started_at.present? && ended_at.nil? && expires_at.future?
end
