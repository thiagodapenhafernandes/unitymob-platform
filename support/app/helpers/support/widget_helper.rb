module Support::WidgetHelper
  def support_unread_count
    return 0 unless support_widget_available?
    Support::Ticket.joins(:account).where(support_accounts: { local_tenant_id: current_tenant.id }, requester_id: current_admin_user.id.to_s).ongoing.unread_responses.count
  end

  def support_widget_available?
    return false if SupportDesk.central? || !current_admin_user || !current_tenant
    account = Support::Account.find_by(local_tenant_id: current_tenant.id)
    account ? account.active? : Support::Registration.enabled?
  end
end
