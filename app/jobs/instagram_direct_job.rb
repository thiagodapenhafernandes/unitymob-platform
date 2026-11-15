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
        existing = lead.persisted? ? lead : nil
        reconciled = Instagram::ContactIdentity.resolve!(tenant: tenant, page: page, sender: sender, event: event, source: existing)
        lead = reconciled if reconciled
        new_lead = lead.new_record?
        if new_lead
          lead.assign_attributes(name: Instagram::ProfileEnrichmentJob::DEFAULT_NAME, origin: "Instagram Direct", status: Lead.default_status)
          Instagram::RoutingContext.apply(lead)
          rules = Instagram::CaptureSettings.new(page, tenant: tenant).rules
          if rules.values.any? { |rule| rule["enabled"] } &&
              MetaFacebookPage.available_for_distribution(tenant.id).exists?(id: page.id)
            lead.other_information = lead.other_information.to_h.merge("instagram_capture" => { "step" => "start" })
          end
          lead = Leads::Intake.receive!(lead)
        end
        lead.lock!
        return if lead.instagram_messages.exists?(message_id: message["mid"])
        context = InstagramMessage.received_context(message)
        referral = message["referral"] || event["referral"]
        context["referral"] = referral.slice("ref", "source", "type", "ad_id").select { |_, value| value.is_a?(String) }.transform_values { |value| value.first(2000) } if referral.is_a?(Hash)
        context["meta_facebook_page_id"] = page.id
        codes = InstagramMessage.new(body: message["text"], context: context).property_reference_codes
        if codes.one? && tenant.habitations.public_property_listable.exists?(codigo: codes.first)
          context["property_code"] = codes.first
        end
        timestamp = Float(event["timestamp"], exception: false)
        occurred_at = timestamp && timestamp.between?(0, 32_503_680_000_000) ? Time.at(timestamp / 1000).utc : Time.current
        lead.instagram_messages.create!(message_id: message["mid"].to_s.first(1000), body: message["text"].to_s.first(20_000), context: context, occurred_at: occurred_at)
        if lead.other_information.to_h["instagram_entry"].blank?
          lead.update!(other_information: lead.other_information.to_h.merge("instagram_entry" => context.merge("message_id" => message["mid"])))
        end
        rules = Instagram::CaptureSettings.new(page, tenant: tenant).rules
        rule_key = lead.other_information.dig('instagram_capture', 'rule_key') || lead.other_information['meta_campaign_id'].to_s
        Instagram::Qualification.capture!(lead, rule: rules.fetch(rule_key, rules.fetch('default')))
        if lead.other_information.dig('instagram_qualification', 'ready') && lead.c2s_existing_id_for(tenant.external_lead_integration).present?
          ExternalLeadMigration::SyncInstagramQualificationJob.perform_later(tenant.id, lead.id)
        end
        page.update!(instagram_received_at: Time.current)
        [lead, new_lead]
      end
      if lead.instagram_capture_pending? || (!new_lead && message["text"].present?)
        Instagram::CaptureJob.perform_later(tenant.id, lead.id)
      end
      Instagram::ProfileEnrichmentJob.perform_later(tenant.id, lead.id) if new_lead
    end
  end
end
