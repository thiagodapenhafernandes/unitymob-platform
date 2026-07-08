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
    # Em deliver_later, Current.tenant pode estar vazio; quando o mailer recebe
    # um lead/tenant nos params, use esse contexto para respeitar SMTP proprio.
    setting = EmailSetting.for(mail_tenant) || EmailSetting.global
    return unless setting&.configured?

    headers[:from] ||= setting.from_address
    # Message-ID no domínio do remetente: o default do Mail usa o hostname da
    # máquina (ex.: MacBook.local) — spam score altíssimo nos filtros.
    headers[:message_id] ||= "<#{SecureRandom.uuid}@#{setting.mail_domain}>" if setting.mail_domain.present?
    headers[:reply_to] ||= setting.reply_to if setting.reply_to.present?
    headers[:delivery_method] = :smtp
    headers[:delivery_method_options] = setting.smtp_settings
  rescue ActiveRecord::StatementInvalid, ActiveRecord::Encryption::Errors::Base => e
    Rails.logger.warn("[ApplicationMailer] SMTP da conta indisponível: #{e.message}")
  end

  def mail_tenant
    params[:tenant].presence ||
      params[:lead]&.tenant ||
      params[:corretor]&.tenant ||
      Current.tenant
  end
end
