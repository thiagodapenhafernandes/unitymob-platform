module Admin
  class ImpersonationsController < BaseController
    def destroy
      impersonated_user = current_admin_user
      original_admin = impersonation_admin_user
      return_to = session.delete(:impersonator_return_to).presence || admin_admin_users_path
      session.delete(:impersonator_admin_user_id)

      unless original_admin
        sign_out(:admin_user)
        redirect_to new_admin_user_session_path, alert: "Sessão de impersonação expirada. Faça login novamente."
        return
      end

      bypass_sign_in(original_admin, scope: :admin_user)

      AccessAuditLog.log!(
        event_type: "impersonation_stop",
        result: "allowed",
        request: request,
        admin_user: original_admin,
        reason: "Admin encerrou impersonação",
        metadata: {
          impersonator_admin_user_id: original_admin.id,
          impersonated_admin_user_id: impersonated_user&.id
        }
      )

      redirect_to return_to, notice: "Você voltou para sua sessão de administrador."
    end
  end
end
