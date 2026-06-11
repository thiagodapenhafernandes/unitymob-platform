class Admin::BaseController < ApplicationController
  before_action :authenticate_admin_user!
  before_action :set_current_admin_user
  before_action :enforce_access_control_policy!
  before_action :prevent_search_indexing
  after_action :record_allowed_admin_access
  layout 'admin'
  
  private
  
  def authenticate_admin_user!
    unless current_admin_user
      redirect_to new_admin_user_session_path, alert: 'Acesso negado. Por favor, faça login.'
    end
  end

  def prevent_search_indexing
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end

  def set_current_admin_user
    Current.admin_user = current_admin_user
  end

  def enforce_access_control_policy!
    return unless current_admin_user
    return if impersonating_admin_user?

    access_result = AccessControl::Policy.call(admin_user: current_admin_user, request: request, controller: self)
    return if access_result.allowed?

    AccessAuditLog.log!(
      event_type: "access_denied",
      result: "denied",
      request: request,
      admin_user: current_admin_user,
      reason: access_result.reason,
      metadata: { trusted_device_id: access_result.device&.id, trusted_device_status: access_result.device&.status }.compact
    )

    @access_audit_denied = true
    sign_out(current_admin_user)
    redirect_to new_admin_user_session_path, alert: access_result.reason
  end
  
  def require_admin!
    unless current_admin_user&.admin?
      redirect_to admin_root_path, alert: 'Acesso negado. Apenas administradores.'
    end
  end

  def check_permission!(action, resource)
    unless current_admin_user&.can?(action, resource)
      AccessAuditLog.log!(
        event_type: "access_denied",
        result: "denied",
        request: request,
        admin_user: current_admin_user,
        reason: "Permissão insuficiente",
        metadata: { required_action: action, required_resource: resource }
      )

      @access_audit_denied = true
      respond_to do |format|
        format.html { redirect_to admin_root_path, alert: "Você não tem permissão para acessar esta área." }
        format.json { render json: { error: "forbidden" }, status: :forbidden }
      end
    end
  end

  def record_allowed_admin_access
    return unless current_admin_user
    return if @access_audit_denied
    return if request.format.json?

    AccessAuditLog.log!(
      event_type: "admin_access",
      result: "allowed",
      request: request,
      admin_user: current_admin_user,
      reason: "Acesso administrativo permitido",
      metadata: {
        response_status: response.status,
        format: request.format&.symbol
      }.compact
    )
  end

  # Retorna scope do usuário para o recurso ("own" ou "all").
  def scope_for_resource(resource)
    current_admin_user&.scope_for(resource) || "own"
  end

  def owns_all_resource?(resource)
    current_admin_user&.owns_all?(resource)
  end

  helper_method :can?, :scope_for_resource, :owns_all_resource?, :impersonating_admin_user?, :impersonation_admin_user

  def can?(action, resource)
    current_admin_user&.can?(action, resource)
  end

  def impersonation_admin_user
    impersonator_id = session[:impersonator_admin_user_id]
    return nil if impersonator_id.blank?

    @impersonation_admin_user ||= AdminUser.find_by(id: impersonator_id)
  end

  def impersonating_admin_user?
    impersonation_admin_user.present? &&
      current_admin_user.present? &&
      current_admin_user.id != impersonation_admin_user.id
  end
end
