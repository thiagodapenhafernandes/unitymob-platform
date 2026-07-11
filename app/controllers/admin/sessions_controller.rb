class Admin::SessionsController < Devise::SessionsController
  include DeviceRequest

  layout 'admin_login'

  def create
    email = params.dig(:admin_user, :email).to_s.strip.downcase
    password = params.dig(:admin_user, :password).to_s
    resource = AdminUser.find_for_authentication(email: email)

    # Espelho (multi-conta) não faz login direto: a credencial é do primário.
    if resource.respond_to?(:mirror?) && resource&.mirror?
      AccessAuditLog.log!(event_type: "login", result: "denied", request: request,
                          admin_user: resource, email: email, reason: "Tentativa de login em usuário espelho")
      flash[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "E-mail")
      redirect_to new_admin_user_session_path
      return
    end

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

      # 2FA: com TOTP ativo, senha correta NÃO loga — abre o desafio.
      if resource.otp_enabled?
        session[:otp_pending_id] = resource.id
        session[:otp_pending_at] = Time.current.to_i
        session[:otp_attempts] = 0
        AccessAuditLog.log!(
          event_type: "two_factor_challenge",
          result: "allowed",
          request: request,
          admin_user: resource,
          email: email,
          reason: "Senha válida — aguardando código TOTP"
        )
        redirect_to admin_two_factor_path
        return
      end

      finish_sign_in!(resource, email, access_result)
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

  # ===== Desafio TOTP (2ª etapa do login) =====
  def two_factor
    return unless ensure_otp_pending!

    render :two_factor
  end

  def verify_two_factor
    resource = ensure_otp_pending!
    return unless resource

    session[:otp_attempts] = session[:otp_attempts].to_i + 1
    if session[:otp_attempts] > 5
      clear_otp_pending!
      AccessAuditLog.log!(event_type: "two_factor_failed", result: "denied", request: request,
                          admin_user: resource, reason: "Tentativas de código esgotadas")
      flash[:alert] = "Muitas tentativas de código. Entre novamente."
      redirect_to new_admin_user_session_path
      return
    end

    code = params[:otp_code].to_s
    backup = code.gsub(/\s+/, "").length >= 10
    if resource.verify_totp!(code) || (backup && resource.verify_backup_code!(code))
      clear_otp_pending!
      metadata = backup ? { backup_code: true, remaining: Array(resource.otp_backup_codes).size } : {}
      AccessAuditLog.log!(event_type: "two_factor_success", result: "allowed", request: request,
                          admin_user: resource, reason: "Código TOTP válido", metadata: metadata)
      finish_sign_in!(resource, resource.email, nil)
    else
      AccessAuditLog.log!(event_type: "two_factor_failed", result: "denied", request: request,
                          admin_user: resource, reason: "Código TOTP inválido")
      flash.now[:alert] = "Código inválido. Confira o aplicativo autenticador."
      render :two_factor, status: :unprocessable_entity
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
    # Roteia por capacidade real, não pelo eixo/cargo. Perfis intermediários com
    # acesso ao admin ficam no painel; usuários field-only seguem para o PWA.
    return admin_system_path if resource.respond_to?(:system_admin?) && resource.system_admin?

    # Celular = PWA: quem loga de iOS/Android aterrissa no app de campo, onde
    # vivem instalação, push e o fluxo mobile (o admin fica para o desktop).
    return field_root_path if mobile_device_request?

    admin_root_path
  end
  
  def after_sign_out_path_for(resource_or_scope)
    new_admin_user_session_path
  end

  private

  # Sessão persistente: emite o cookie "lembrar-me" para o PWA não deslogar
  # sozinho quando o iOS descarta a sessão. Só o logout explícito encerra.
  def finish_sign_in!(resource, email, access_result)
    resource.remember_me = true
    sign_in(resource_name, resource)
    AccessAuditLog.log!(
      event_type: "login",
      result: "allowed",
      request: request,
      admin_user: resource,
      email: email,
      reason: "Credenciais válidas",
      metadata: { trusted_device_id: access_result&.device&.id, trusted_device_status: access_result&.device&.status }.compact
    )
    redirect_to after_sign_in_path_for(resource)
  end

  # Pendência de TOTP expira em 5 minutos; sem pendência válida, volta ao login.
  def ensure_otp_pending!
    pending_id = session[:otp_pending_id]
    pending_at = session[:otp_pending_at].to_i
    resource = pending_id && AdminUser.find_by(id: pending_id)

    if resource.nil? || pending_at.zero? || Time.current.to_i - pending_at > 5.minutes.to_i || !resource.otp_enabled?
      clear_otp_pending!
      redirect_to new_admin_user_session_path, alert: "Sessão de verificação expirada. Entre novamente."
      return nil
    end

    @otp_resource = resource
  end

  def clear_otp_pending!
    session.delete(:otp_pending_id)
    session.delete(:otp_pending_at)
    session.delete(:otp_attempts)
  end
end
