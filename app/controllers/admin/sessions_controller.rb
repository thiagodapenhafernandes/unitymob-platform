class Admin::SessionsController < Devise::SessionsController
  layout 'admin_login'

  def create
    email = params.dig(:admin_user, :email).to_s.strip.downcase
    password = params.dig(:admin_user, :password).to_s
    resource = AdminUser.find_for_authentication(email: email)

    if resource&.valid_password?(password)
      access_result = AccessControl::Policy.call(admin_user: resource, request: request, controller: self)

      unless access_result.allowed?
        AccessAuditLog.log!(
          event_type: "login",
          result: "denied",
          request: request,
          admin_user: resource,
          email: email,
          reason: access_result.reason,
          metadata: { trusted_device_id: access_result.device&.id, trusted_device_status: access_result.device&.status }.compact
        )
        flash[:alert] = access_result.reason
        redirect_to new_admin_user_session_path
        return
      end

      # Sessão persistente: emite o cookie "lembrar-me" para o PWA não deslogar
      # sozinho quando o iOS descarta a sessão. Só o logout explícito encerra.
      resource.remember_me = true
      sign_in(resource_name, resource)
      AccessAuditLog.log!(
        event_type: "login",
        result: "allowed",
        request: request,
        admin_user: resource,
        email: email,
        reason: "Credenciais válidas",
        metadata: { trusted_device_id: access_result.device&.id, trusted_device_status: access_result.device&.status }.compact
      )
      redirect_to after_sign_in_path_for(resource)
    else
      AccessAuditLog.log!(
        event_type: "login",
        result: "denied",
        request: request,
        admin_user: resource,
        email: email,
        reason: resource ? "Senha inválida" : "Usuário não encontrado"
      )
      flash[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "E-mail")
      redirect_to new_admin_user_session_path
    end
  end

  def destroy
    AccessAuditLog.log!(
      event_type: "logout",
      result: "allowed",
      request: request,
      admin_user: current_admin_user,
      reason: "Sessão encerrada pelo usuário"
    )

    super
  end
  
  def after_sign_in_path_for(resource)
    # Corretor (não-admin) vai direto pro PWA /field — ambiente mobile-first
    # com hub de atalhos (captações, leads, imóveis, check-in).
    # Admin continua no painel tradicional /admin.
    return field_root_path if resource.respond_to?(:admin?) && !resource.admin?
    admin_root_path
  end
  
  def after_sign_out_path_for(resource_or_scope)
    new_admin_user_session_path
  end
end
