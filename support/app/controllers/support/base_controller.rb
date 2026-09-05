class Support::BaseController < (SupportDesk.central? ? ::ApplicationController : ::Admin::BaseController)
  before_action :require_support!
  helper_method :support_operator?, :support_account
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  private

  def support_operator? = SupportDesk.central? && current_staff.operator?
  def support_account
    @support_account ||= Support::Registration.local_account(current_tenant) if !SupportDesk.central? && current_tenant
  end
  def require_support!
    allowed = SupportDesk.central? ? current_staff&.operator? : current_admin_user.present? && support_account&.active?
    head :forbidden unless allowed
  end
  def visible_tickets
    return Support::Ticket.all if support_operator?
    scope = support_account.tickets
    current_admin_user.tenant_owner? ? scope : scope.where(requester_id: current_admin_user.id.to_s)
  end
  def actor = support_operator? ? "staff:#{current_staff.id}" : "user:#{current_admin_user.id}"
end
