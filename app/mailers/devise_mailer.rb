# Mailer do Devise (recuperação de senha) com o SMTP da conta do usuário e o
# mesmo guard dos demais mailers: sem SMTP configurado, o envio é suprimido
# em vez de tentar localhost:25.
class DeviseMailer < Devise::Mailer
  protected

  # Remove remetente/reply_to globais do Devise para o ApplicationMailer
  # preencher com os dados da conta (EmailSetting#from_address/#reply_to).
  def headers_for(action, opts)
    super.except(:from, :reply_to)
  end

  private

  # O SMTP de um e-mail do Devise é o da conta do usuário destinatário
  # (o record sobrevive à serialização do deliver_later via GlobalID).
  def mail_tenant
    resource.try(:tenant) || super
  end
end
