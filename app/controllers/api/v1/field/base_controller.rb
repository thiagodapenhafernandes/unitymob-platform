# frozen_string_literal: true

# Base da API mobile (app híbrido). Autentica por Bearer/JWT (segunda
# estratégia Warden do scope :admin_user) em vez de sessão/cookie — nunca
# usa nem afeta o fluxo de Admin::BaseController/Field::BaseController.
# Falhas respondem sempre em JSON, nunca com redirect.
module Api
  module V1
    module Field
      class BaseController < ApplicationController
        include UserActivityTrackable

        # Autenticado por Bearer, não por cookie de sessão — não há token CSRF
        # (nem sentido em exigir um: CSRF explora cookies ambientes, e este
        # endpoint não usa cookie nenhum para autenticar).
        skip_before_action :verify_authenticity_token, raise: false

        before_action :authenticate_admin_user!
        before_action :set_current_context
        before_action :ensure_tenant_context!
        before_action :enforce_access_control_policy!

        private

        def set_current_context
          Current.admin_user = current_admin_user
          Current.tenant = current_admin_user&.tenant
        end

        def current_tenant
          Current.tenant || current_admin_user&.tenant
        end
        helper_method :current_tenant

        def ensure_tenant_context!
          return if current_tenant.present?

          render json: { error: "tenant_not_found" }, status: :unprocessable_entity
        end

        # Reaproveita a mesma política de IP allowlist / dispositivo confiável do
        # admin e do Field (app/services/access_control/policy.rb). Atenção: para
        # tenants com "dispositivo confiável" exigido, o registro de confiança
        # hoje depende de cookie de navegador — um app mobile puro (sem WebView)
        # ainda não tem como ficar "trusted" por esse fluxo. Enquanto isso não for
        # resolvido, contas nesses tenants recebem 403 aqui até existir um fluxo
        # de confiança de dispositivo dedicado ao mobile.
        def enforce_access_control_policy!
          access_result = AccessControl::Policy.call(admin_user: current_admin_user, request: request, controller: self)
          return if access_result.allowed?

          AccessAuditLog.log!(
            event_type: "access_denied",
            result: "denied",
            request: request,
            admin_user: current_admin_user,
            reason: access_result.reason,
            metadata: { trusted_device_id: access_result.device&.id, trusted_device_status: access_result.device&.status, area: "api_mobile" }.compact
          )

          render json: { error: "access_denied", reason: access_result.reason }, status: :forbidden
        end
      end
    end
  end
end
