class Admin::BaseController < ApplicationController
  include Admin::ContextItems

  before_action :authenticate_admin_user!
  before_action :set_current_admin_user
  before_action :ensure_tenant_context_selected!
  before_action :enforce_access_control_policy!
  before_action :prevent_search_indexing
  around_action :measure_admin_page_render
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

  def measure_admin_page_render
    @admin_render_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    if @admin_render_started_at
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @admin_render_started_at) * 1000).round(1)
      @admin_render_duration_ms = duration_ms

      unless response.committed?
        response.set_header("X-Admin-Render-Duration-Ms", duration_ms.to_s)
        response.set_header("X-Admin-Page", "#{controller_path}##{action_name}")
        response.set_header("Server-Timing", "admin_render;dur=#{duration_ms}")
      end

      Rails.logger.info(
        "[admin_render] page=#{controller_path}##{action_name} status=#{response.status} duration_ms=#{duration_ms} " \
        "method=#{request.request_method} path=#{request.fullpath}"
      )
    end
  end

  def set_current_admin_user
    Current.admin_user = current_admin_user
    Current.tenant = resolve_admin_tenant_context
  end

  def resolve_admin_tenant_context
    return current_admin_user&.tenant unless current_admin_user&.system_admin?

    session.delete(:admin_current_tenant_id)
    nil
  end

  def ensure_tenant_context_selected!
    return unless current_admin_user&.system_admin?
    return if Current.tenant.present?
    return if controller_path == "admin/system"

    redirect_to admin_system_path, alert: "Admin do Sistema acessa áreas da conta apenas por impersonação."
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
    unless tenant_owner?
      redirect_to admin_root_path, alert: 'Acesso negado. Apenas administradores.'
    end
  end

  def current_tenant
    Current.tenant || (current_admin_user&.system_admin? ? nil : current_admin_user&.tenant)
  end
  helper_method :current_tenant

  def selected_tenant_context?
    current_tenant.present?
  end
  helper_method :selected_tenant_context?

  def system_admin?
    current_admin_user&.system_admin?
  end
  helper_method :system_admin?

  def tenant_owner?
    current_admin_user&.tenant_owner?
  end
  helper_method :tenant_owner?

  def require_system_admin!
    unless system_admin?
      redirect_to admin_root_path, alert: 'Acesso restrito ao Admin do Sistema.'
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

  # Retorna scope do usuário para o recurso ("own", "team" ou "all").
  def scope_for_resource(resource)
    current_admin_user&.scope_for(resource) || "own"
  end

  def owns_all_resource?(resource)
    current_admin_user&.owns_all?(resource)
  end

  # IDs do próprio usuário + subárvore (equipe).
  def team_scope_ids
    current_admin_user&.team_scope_ids || []
  end

  # Mostra o toggle "+ equipe"? Só quando o perfil tem escopo "team" para o recurso
  # E o usuário tem subordinados na árvore de gestão.
  def team_available?(resource)
    return false unless current_admin_user
    current_admin_user.can_view_team?(resource) && current_admin_user.descendant_ids.any?
  end

  # Estado efetivo do toggle. Opt-out: ligado por padrão quando disponível;
  # só desliga quando o usuário envia explicitamente team=0.
  def include_team?(resource)
    return false unless team_available?(resource)
    params[:team].to_s != "0"
  end

  # IDs dos donos visíveis para o recurso. nil = sem filtro (vê tudo, escopo "all"/admin).
  def visible_owner_ids(resource)
    return nil if owns_all_resource?(resource)
    return team_scope_ids if include_team?(resource)
    [current_admin_user&.id].compact
  end

  # Conjunto de owner-ids que o usuário pode ACESSAR (nível de registro), ignorando o
  # toggle "+ equipe" (que é só recorte de listagem). nil = sem restrição (escopo total).
  def accessible_owner_ids(resource)
    return nil if owns_all_resource?(resource)
    current_admin_user&.can_view_team?(resource) ? team_scope_ids : [current_admin_user&.id].compact
  end

  # O usuário pode acessar um registro cujo dono é um dos owner_ids?
  def owner_in_scope?(resource, *owner_ids)
    allowed = accessible_owner_ids(resource)
    return true if allowed.nil?
    ids = owner_ids.flatten.compact.map(&:to_i)
    ids.intersect?(allowed)
  end

  def restrict_owner_param_to_scope!(attrs, resource, key: :admin_user_id)
    value = attrs[key]
    return attrs if value.blank?
    return attrs if owner_in_scope?(resource, value)

    attrs.delete(key)
    attrs
  end

  helper_method :can?, :scope_for_resource, :owns_all_resource?,
                :team_scope_ids, :team_available?, :include_team?,
                :impersonating_admin_user?, :impersonation_admin_user

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
