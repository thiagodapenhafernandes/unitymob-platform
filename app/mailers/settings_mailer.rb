class SettingsMailer < ApplicationMailer
  # E-mail de teste disparado a partir da tela de configuração de SMTP.
  def smtp_test
    @setting = params[:setting]
    from_label = @setting.from_name.presence || "Plataforma"

    mail(to: params[:to], subject: "Teste de SMTP — #{from_label}")
  end
end
