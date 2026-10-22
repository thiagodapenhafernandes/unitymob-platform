class Admin::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  before_action :authenticate_admin_user!
  before_action :require_meta_integration_permission!, only: :facebook

  def facebook
    auth = request.env["omniauth.auth"]
    
    # A reconexão mantém a seleção local da conta do usuário autenticado.
    integration = UserMetaIntegration.find_or_initialize_by(admin_user: current_admin_user, tenant_id: current_admin_user.tenant_id)
    
    Meta::ConnectionCompletion.call(integration: integration, identity: {
      'access_token' => auth.credentials.token, 'facebook_user_id' => auth.uid, 'name' => auth.info.name, 'email' => auth.info.email
    })
    redirect_to admin_meta_integrations_path, notice: "Facebook conectado. Estamos preparando os recursos em segundo plano."
  rescue => e
    reason = UserMetaIntegration.sync_failure_reason(e)
    integration.update!(sync_status: "failed", sync_message: reason, last_sync_error: reason) if integration&.persisted?
    Rails.logger.error "Omniauth Error: #{e.class}"
    redirect_to admin_meta_integrations_path, alert: "Não foi possível concluir a conexão. #{reason}"
  end

  def failure
    redirect_to admin_meta_integrations_path, alert: "Falha na autenticação: #{failure_message}"
  end

  private

  def require_meta_integration_permission!
    return if current_admin_user&.can?(:manage, :integracoes)

    redirect_to admin_root_path, alert: "Você não tem permissão para conectar integrações."
  end
end
