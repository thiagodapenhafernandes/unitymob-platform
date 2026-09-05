module Support::WidgetHelper
  def support_widget_available?
    return false if SupportDesk.central? || !current_admin_user || !current_tenant
    account = Support::Account.find_by(local_tenant_id: current_tenant.id)
    account ? account.active? : Support::Registration.enabled?
  end
end
