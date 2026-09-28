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
