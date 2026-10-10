class Admin::PasswordsController < Devise::PasswordsController
  # Sem SMTP disponível para a conta, o e-mail de reset seria suprimido pelo
  # guard do ApplicationMailer — avisa na tela em vez de fingir que enviou.
  # Mesma resposta exista ou não o e-mail (sem enumeração de contas).
  def create
    unless reset_email_available?
      redirect_to new_admin_user_password_path,
                  alert: "Recuperação de senha por e-mail indisponível no momento. Fale com o administrador da conta."
      return
    end

    super
  end

  # Pós-reset nunca cria sessão direta (sign_in_after_reset_password=false):
  # conta com TOTP segue para o mesmo desafio do login; sem TOTP, volta ao
  # login para autenticar com a nova senha.
  def update
    super do |resource|
      next if resource.errors.any?

      if resource.otp_enabled?
        sign_out(resource) if signed_in?(resource_name)
        session[:otp_pending_id] = resource.id
        session[:otp_pending_at] = Time.current.to_i
        session[:otp_attempts] = 0
      end
    end
  end

  protected

  def after_resetting_password_path_for(resource)
    return admin_two_factor_path if resource.otp_enabled?

    new_admin_user_session_path
  end

  private

  # Espelha a resolução do DeviseMailer (SMTP da conta do usuário, com
  # fallback para o global): prevê se este reset vai ser entregue.
  def reset_email_available?
    tenant = AdminUser.find_for_authentication(email: reset_email)&.tenant || Current.tenant
    setting = EmailSetting.for(tenant) || EmailSetting.global
    setting&.configured?
  rescue StandardError => e
    Rails.logger.warn("[Passwords] SMTP indisponível para reset: #{e.message}")
    false
  end

  def reset_email
    params.dig(:admin_user, :email).to_s.strip.downcase
  end
end
