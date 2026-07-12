class SystemHealthAlertMailer < ApplicationMailer
  def degraded
    @status = params[:status].to_s
    @findings = Array(params[:findings])
    recipients = Array(params[:recipients]).map(&:to_s).map(&:strip).reject(&:blank?)
    return if recipients.empty?

    mail(to: recipients, subject: "[UNITYMOB] Saúde da plataforma: #{@status}")
  end
end
