# Alerta do rastreador interno de erros: fingerprint novo (ou reincidente após
# resolvido). Caminho global (system-level): usa o SMTP singleton da plataforma
# via ApplicationMailer/EmailSetting; destinatários vêm de ENV['ERROR_ALERT_EMAIL']
# (lista separada por vírgula). Throttle por fingerprint em ErrorEvent.deliver_alert.
class ErrorAlertMailer < ApplicationMailer
  def new_error_event
    @error_event = ErrorEvent.find_by(id: params[:error_event_id])
    return if @error_event.nil?

    recipients = Array(params[:recipients]).presence ||
                 ENV["ERROR_ALERT_EMAIL"].to_s.split(",").map(&:strip).reject(&:empty?)
    return if recipients.blank?

    mail(
      to: recipients,
      subject: "[ERROR_TRACKER] #{@error_event.exception_class}: #{@error_event.message.to_s.truncate(80)}"
    )
  end
end
