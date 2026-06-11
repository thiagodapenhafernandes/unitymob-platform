# frozen_string_literal: true

# Base para todos os controllers sob /field (PWA de corretores).
# - Hub (home, lista, etc) sempre acessível pra corretor logado.
# - Check-in específico exige FieldFeatureGate.field_checkin_enabled?.
module Field
  class BaseController < ApplicationController
    include FieldFeatureGate

    before_action :authenticate_admin_user!
    before_action :enforce_access_control_policy!
    after_action :record_allowed_field_access
    layout "field"

    private

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

    def record_allowed_field_access
      return unless current_admin_user
      return if @access_audit_denied
      return if request.format.json?

      AccessAuditLog.log!(
        event_type: "admin_access",
        result: "allowed",
        request: request,
        admin_user: current_admin_user,
        reason: "Acesso restrito permitido",
        metadata: {
          area: "field",
          response_status: response.status,
          format: request.format&.symbol
        }.compact
      )
    end

    # Exigido pelas rotas de check-in/pings/manual (não pela home).
    def ensure_field_agent!
      return if current_admin_user&.field_agent_enabled?

      if request.format.json?
        render json: { error: "not_a_field_agent" }, status: :forbidden
      else
        redirect_to field_root_path, alert: "Você não está habilitado como corretor de campo."
      end
    end
  end
end
