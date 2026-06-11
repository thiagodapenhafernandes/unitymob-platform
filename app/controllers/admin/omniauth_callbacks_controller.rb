class Admin::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def facebook
    auth = request.env["omniauth.auth"]
    
    # Busca ou cria a integração para o AdminUser atual
    integration = UserMetaIntegration.find_or_initialize_by(admin_user: current_admin_user)
    
    # Trocar token de curto prazo por longo prazo (opcional, mas recomendado)
    token_info = Facebook::MetaService.exchange_access_token(auth.credentials.token)
    
    integration.update!(
      access_token: token_info&.fetch("access_token", nil) || auth.credentials.token,
      facebook_user_id: auth.uid,
      name: auth.info.name,
      email: auth.info.email,
      token_expires_at: token_info&.fetch("expires_in", nil) ? Time.current + token_info["expires_in"].to_i.seconds : nil
    )

    redirect_to admin_meta_integrations_path, notice: "Facebook conectado com sucesso! Agora sincronize suas páginas."
  rescue => e
    Rails.logger.error "Omniauth Error: #{e.message}"
    redirect_to admin_meta_integrations_path, alert: "Erro ao conectar com Facebook: #{e.message}"
  end

  def failure
    redirect_to admin_meta_integrations_path, alert: "Falha na autenticação: #{failure_message}"
  end
end
