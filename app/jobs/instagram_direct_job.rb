class InstagramDirectJob < ApplicationJob
  queue_as :sync
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(profile_id, event)
    return unless event.is_a?(Hash) && event["message"].is_a?(Hash)
    message = event["message"]
    sender = event.dig("sender", "id").to_s
    return if message["is_echo"] || message["is_deleted"] || message["mid"].blank? || message["mid"].to_s.length > 1000 || sender.blank? || sender == profile_id
    return unless sender.match?(/\A[0-9]{1,100}\z/) && profile_id.match?(/\A[0-9]{1,100}\z/)
    return unless event.dig("recipient", "id").to_s == profile_id
    page = MetaFacebookPage.find_by(instagram_id: profile_id, instagram_enabled: true)
    return unless page
    tenant = page.user_meta_integration.tenant
    return unless tenant

    return if Instagram::InternalSender.match?(tenant: tenant, page: page, sender_id: sender)

    Current.set(tenant: tenant) do
      # ponytail: serialize per profile; use per-contact locks if inbound volume requires it.
      lead, new_lead = page.with_lock do
        return unless page.instagram_enabled? && page.instagram_id == profile_id
        lead = tenant.leads.find_or_initialize_by(instagram_account_id: profile_id, instagram_scoped_id: sender)
        new_lead = lead.new_record?
        if new_lead
          lead.assign_attributes(name: Instagram::ProfileEnrichmentJob::DEFAULT_NAME, origin: "Instagram Direct", status: Lead.default_status)
          rules = Instagram::CaptureSettings.new(page, tenant: tenant).rules
          if rules.values.any? { |rule| rule["enabled"] } &&
              MetaFacebookPage.available_for_distribution(tenant.id).exists?(id: page.id)
            lead.other_information = lead.other_information.to_h.merge("instagram_capture" => { "step" => "start" })
          end
          lead = Leads::Intake.receive!(lead)
        end
        next [lead, false] if lead.instagram_messages.exists?(message_id: message["mid"])
        context = {}
        referral = message["referral"] || event["referral"]
        context["referral"] = referral.slice("ref", "source", "type", "ad_id").select { |_, value| value.is_a?(String) }.transform_values { |value| value.first(2000) } if referral.is_a?(Hash)
        context["meta_facebook_page_id"] = page.id if context.dig("referral", "ad_id").present?
        story = message.dig("reply_to", "story")
        context["story_id"] = story["id"] if story.is_a?(Hash)
        timestamp = Float(event["timestamp"], exception: false)
        occurred_at = timestamp && timestamp.between?(0, 32_503_680_000_000) ? Time.at(timestamp / 1000).utc : Time.current
        lead.instagram_messages.create!(message_id: message["mid"].to_s.first(1000), body: message["text"].to_s.first(20_000), context: context, occurred_at: occurred_at)
        if lead.other_information.to_h["instagram_entry"].blank?
          lead.update!(other_information: lead.other_information.to_h.merge("instagram_entry" => context.merge("message_id" => message["mid"])))
        end
        page.update!(instagram_received_at: Time.current)
        [lead, new_lead]
      end
      Instagram::CaptureJob.perform_later(tenant.id, lead.id) if lead.instagram_capture_pending?
      Instagram::ProfileEnrichmentJob.perform_later(tenant.id, lead.id) if new_lead
    end
  end
end
