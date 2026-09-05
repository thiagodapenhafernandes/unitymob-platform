class LoginMailer < ActionMailer::Base
  # Códigos de autenticação não devem aparecer nos logs de entrega.
  self.logger = nil
  default from: -> { ENV.fetch('SMTP_FROM', ENV.fetch('SMTP_USERNAME', 'contato@unitymob.com.br')) }

  def verification(staff, code)
    mail(to: staff.email, subject: 'Seu código de acesso à Central Unitymob') do |format|
      format.text { render plain: "Seu código de acesso é: #{code}\n\nEle vale por 10 minutos e só pode ser usado uma vez.\n\nSe você não tentou entrar na Central Unitymob, ignore esta mensagem.\n\nEquipe Unitymob" }
    end
  end
end
