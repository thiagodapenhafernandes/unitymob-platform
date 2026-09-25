class ApplicationMailer < ActionMailer::Base
  self.delivery_job = ResilientMailDeliveryJob

  default from: "from@example.com"
  layout "mailer"

  # Aplica o SMTP configurado na conta (EmailSetting) a cada e-mail, quando
  # estiver pronto. Sem SMTP configurado e com o default do ambiente em :smtp
  # (produção), descarta o envio em vez de tentar localhost:25 e gerar
  # retries/falhas na fila. Ambientes com outro delivery (dev/test) seguem
  # o comportamento padrão.
  def mail(headers = {}, &block)
    setting = account_smtp_setting
    apply_account_smtp(headers, setting) if setting&.configured?
    message = super(headers, &block)
    message.perform_deliveries = false if suppress_unconfigured_delivery?(setting)
    message
  end

  private

  def account_smtp_setting
    @account_smtp_setting ||= begin
      # Em deliver_later, Current.tenant pode estar vazio; quando o mailer recebe
      # um lead/tenant nos params, use esse contexto para respeitar SMTP proprio.
      EmailSetting.for(mail_tenant) || EmailSetting.global
    rescue ActiveRecord::StatementInvalid, ActiveRecord::Encryption::Errors::Base => e
      Rails.logger.warn("[ApplicationMailer] SMTP da conta indisponível: #{e.message}")
      nil
    end
  end

  def suppress_unconfigured_delivery?(setting)
    return false if setting&.configured?

    ActionMailer::Base.delivery_method == :smtp
  end

  def apply_account_smtp(headers, setting)
    headers[:from] ||= setting.from_address
    # Message-ID no domínio do remetente: o default do Mail usa o hostname da
    # máquina (ex.: MacBook.local) — spam score altíssimo nos filtros.
    headers[:message_id] ||= "<#{SecureRandom.uuid}@#{setting.mail_domain}>" if setting.mail_domain.present?
    headers[:reply_to] ||= setting.reply_to if setting.reply_to.present?
    headers[:delivery_method] = :smtp
    headers[:delivery_method_options] = setting.smtp_settings
  end

  def mail_tenant
    params[:tenant].presence ||
      params[:lead]&.tenant ||
      params[:corretor]&.tenant ||
      Current.tenant
  end
end
