class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  # Aplica o SMTP configurado na conta (EmailSetting) a cada e-mail, quando
  # estiver pronto. Mantém o comportamento padrão do ambiente caso contrário.
  def mail(headers = {}, &block)
    apply_account_smtp(headers)
    super(headers, &block)
  end

  private

  def apply_account_smtp(headers)
    setting = EmailSetting.instance
    return unless setting.configured?

    headers[:from] ||= setting.from_address
    headers[:reply_to] ||= setting.reply_to if setting.reply_to.present?
    headers[:delivery_method] = :smtp
    headers[:delivery_method_options] = setting.smtp_settings
  rescue ActiveRecord::StatementInvalid, ActiveRecord::Encryption::Errors::Base => e
    Rails.logger.warn("[ApplicationMailer] SMTP da conta indisponível: #{e.message}")
  end
end
