module Api
  module V1
    module BrowserExtension
      # Não herda callbacks públicos, cookies, redirecionamentos ou autenticação Warden.
      class BaseController < ActionController::API
        before_action :prevent_cache
        before_action :authenticate_grant!
        around_action :with_tenant_context
        rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "not_found" }, status: :not_found }

        private

        attr_reader :grant

        def prevent_cache
          response.set_header("Cache-Control", "no-store")
        end

        def authenticate_grant!
          scheme, token = request.authorization.to_s.split(" ", 2)
          @grant = BrowserExtensionGrant.from_token(token) if scheme == "Bearer"
          unless grant&.accessible?
            return render json: { error: "unauthorized" }, status: :unauthorized
          end
          access = AccessControl::Policy.call(admin_user: grant.admin_user, request: request, trusted_device: grant.trusted_device)
          render json: { error: "access_denied" }, status: :forbidden unless access.allowed?
        end

        def with_tenant_context(&block)
          Current.set(tenant: grant.tenant, admin_user: grant.admin_user, &block)
        end

        def lead_scope
          scope = grant.tenant.leads
          return scope if grant.admin_user.owns_all?(:leads)

          ids = grant.admin_user.can_view_team?(:leads) ? grant.admin_user.team_scope_ids : [grant.admin_user_id]
          scope.where(admin_user_id: ids)
        end
      end
    end
  end
end
