class HabitationIntakeReviewNotifier
  def initialize(habitation:, actor:, event:, notes: nil, return_reason: nil, property_setting: nil)
    @habitation = habitation
    @actor = actor
    @event = event.to_s
    @notes = notes
    @return_reason = return_reason
    @property_setting = property_setting || PropertySetting.instance
  end

  def call
    return unless @habitation.present?

    notify_internal!
    notify_email!
  end

  private

  def notify_internal!
    return unless property_setting&.notify_internal_review_events

    recipients = internal_recipients
    return if recipients.blank?

    recipients.each do |admin_user|
      begin
        Notifications::PushDispatcher.deliver(
          admin_user_id: admin_user.id,
          title: event_title,
          body: event_body,
          url: admin_capture_url
        )
      rescue StandardError => error
        Rails.logger.warn("[ReviewNotifier] push falhou para ##{admin_user.id}: #{error.class} #{error.message}")
      end
    end
  end

  def notify_email!
    return unless property_setting&.notify_email_review_events
    emails = property_setting.review_notification_email_addresses
    return if emails.blank?

    begin
      HabitationIntakeReviewMailer.with(
        habitation: @habitation,
        event: @event,
        actor: @actor,
        notes: @notes,
        return_reason: @return_reason
      ).review_transition.deliver_later(to: emails)
    rescue StandardError => error
      Rails.logger.warn("[ReviewNotifier] email falhou: #{error.class} #{error.message}")
    end
  end

  def internal_recipients
    @internal_recipients ||= AdminUser
      .active
      .includes(:profile)
      .select { |user| user.admin? || user.can?(:review, :captacoes) }
  end

  def property_setting
    @property_setting
  end

  def actor_name
    @actor&.name.presence || @actor&.email || "Sistema"
  end

  def admin_capture_url
    "/admin/captacoes/#{@habitation.id}"
  end

  def event_label
    case @event
    when "submit_for_review"
      "Captação enviada para revisão"
    when "approve"
      "Captação aprovada"
    when "return_to_broker"
      "Captação devolvida ao corretor"
    when "release_to_site"
      "Captação publicada no site"
    else
      "Atualização de revisão da captação"
    end
  end

  def event_title
    "#{event_label} (#{@habitation.codigo || @habitation.id})"
  end

  def event_body
    details = [habitation_label, "Responsável: #{actor_name}"]
    details << "Motivo: #{@return_reason}" if @return_reason.present?
    details << "Nota interna: #{@notes}" if @notes.present?
    "#{details.join(' · ')}"
  end

  def habitation_label
    [
      @habitation.titulo_anuncio.presence || @habitation.categoria,
      @habitation.city.presence || @habitation.cidade,
      @habitation.intake_status_label
    ].compact.join(" · ")
  end
end
