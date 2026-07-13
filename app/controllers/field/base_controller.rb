# frozen_string_literal: true

# Base para todos os controllers sob /field (PWA de corretores).
# - Hub (home, lista, etc) sempre acessível pra corretor logado.
# - Check-in específico exige FieldFeatureGate.field_checkin_enabled?.
module Field
  class BaseController < ApplicationController
    include FieldFeatureGate
    include DeviceRequest

    prepend_before_action :redirect_desktop_to_admin
    before_action :authenticate_admin_user!
    before_action :set_current_tenant
    before_action :ensure_tenant_context!
    before_action :enforce_access_control_policy!
    before_action :enforce_two_factor_setup!
    layout "field"

    private

    # O Field é a experiência mobile/PWA. Navegação HTML no desktop pertence
    # ao workspace administrativo, inclusive para corretores.
    def redirect_desktop_to_admin
      return unless desktop_device_request?
      return unless request.get? || request.head?
      return unless request.format.html?

      redirect_to admin_root_path
    end

    def enforce_two_factor_setup!
      return unless current_admin_user
      return unless current_admin_user.two_factor_required? && !current_admin_user.otp_enabled?

      redirect_to admin_two_factor_settings_path,
                  alert: "Sua conta exige verificação em duas etapas. Configure para continuar."
    end

    def set_current_tenant
      Current.admin_user = current_admin_user
      Current.tenant = current_admin_user&.tenant
    end

    def current_tenant
      Current.tenant || current_admin_user&.tenant
    end
    helper_method :current_tenant

    def ensure_tenant_context!
      return if current_tenant.present?

      if current_admin_user&.system_admin?
        redirect_to admin_system_path, alert: "Admin do Sistema acessa o Field apenas por uma conta vinculada."
      else
        sign_out(:admin_user)
        redirect_to new_admin_user_session_path, alert: "Não foi possível identificar sua conta. Entre novamente."
      end
    end

    def enforce_access_control_policy!
      access_result = AccessControl::Policy.call(admin_user: current_admin_user, request: request, controller: self)
      return if access_result.allowed?

      AccessAuditLog.log!(
        event_type: "access_denied",
        result: "denied",
        request: request,
        admin_user: current_admin_user,
        reason: access_result.reason,
        metadata: { trusted_device_id: access_result.device&.id, trusted_device_status: access_result.device&.status, area: "field" }.compact
      )

      @access_audit_denied = true
      sign_out(current_admin_user)
      redirect_to new_admin_user_session_path, alert: access_result.reason
    end

    # Exigido pelas rotas de check-in/pings/manual (não pela home).
    def ensure_field_agent!
      return if FieldFeatureGate.field_agent_allowed?(current_admin_user, tenant: current_tenant)

      if request.format.json?
        render json: { error: "not_a_field_agent" }, status: :forbidden
      else
        redirect_to field_root_path, alert: "Check-in indisponível para sua operação."
      end
    end
  end
end
