class HabitationIntakeReviewMailer < ApplicationMailer
  def review_transition
    @habitation = params[:habitation]
    @event = params[:event].to_s
    @actor = params[:actor]
    @notes = params[:notes]
    @return_reason = params[:return_reason]
    recipients = Array(params[:to]).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    return if recipients.blank? || @habitation.blank?

    mail(
      to: recipients,
      subject: subject,
      reply_to: ContactSetting.instance.email_primary
    )
  end

  private

  def event_label
    case @event
    when "submit_for_review"
      "enviada para revisão administrativa"
    when "approve"
      "aprovada pelo administrativo"
    when "return_to_broker"
      "devolvida ao corretor"
    when "release_to_site"
      "publicada no site"
    else
      "atualizada"
    end
  end

  def actor_name
    @actor&.name.presence || @actor&.email || "Sistema"
  end

  def subject
    "Captação #{@habitation.codigo.presence || @habitation.id} #{event_label}"
  end

  def habitation_label
    [
      @habitation.categoria,
      @habitation.titulo_anuncio,
      @habitation.codigo.presence || @habitation.id
    ].compact_blank.join(" · ")
  end
end
