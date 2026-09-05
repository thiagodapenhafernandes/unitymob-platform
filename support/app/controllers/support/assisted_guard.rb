module Support::AssistedGuard
  extend ActiveSupport::Concern
  included do
    prepend_before_action :check_support_session
    after_action :audit_support_operation
    helper_method :support_access_session
  end

  def support_access_session
    @support_access_session ||= Support::AccessSession.find_by(id: session[:support_access_id]) if session[:support_access_id]
  end

  private

  def check_support_session
    return unless session[:support_access_id]
    grant = support_access_session
    user = request.env["warden"]&.user(:admin_user)
    unless grant&.live? && user&.active? && !user.system_admin? && user.id.to_s == grant.requester_id && user.tenant_id == grant.account.local_tenant_id
      grant.update!(ended_at: Time.current) if grant && !grant.ended_at
      request.env["warden"]&.logout(:admin_user)
      reset_session
      return redirect_to "/admin/sign_in", alert: "O acesso do suporte terminou."
    end
    unless Support::AssistedPolicy.allowed?(controller_path, action_name) && !support_nested_destruction?(params.to_unsafe_h)
      Support::Audit.create!(account_id: grant.account_id, ticket_id: grant.ticket_id, actor: "staff:#{grant.operator_id}", action: "access_denied", details: { controller: controller_path, action: action_name })
      render plain: "Esta ação não está disponível no acesso do suporte.", status: :forbidden
    end
  end

  def support_nested_destruction?(value)
    case value
    when Hash
      value.any? { |key, item| (key.to_s == "_destroy" && ActiveModel::Type::Boolean.new.cast(item)) || support_nested_destruction?(item) }
    when Array
      value.any? { |item| support_nested_destruction?(item) }
    else
      false
    end
  end

  def audit_support_operation
    grant = support_access_session
    return unless grant
    Support::Audit.create!(account_id: grant.account_id, ticket_id: grant.ticket_id, actor: "staff:#{grant.operator_id}", action: "assisted_request",
      details: { requester_id: grant.requester_id, controller: controller_path, action: action_name, record_id: params[:id].to_s.first(80), method: request.method, status: response.status, request_id: request.request_id })
  end
end
