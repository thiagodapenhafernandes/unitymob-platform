module Leads
  # Toda entrada consulta a identidade da conta antes de criar um cadastro.
  class Intake
    def self.create!(tenant:, **attributes)
      receive!(tenant.leads.new(attributes))
    end

    def self.matches(lead)
      raise ArgumentError, "Conta obrigatória" unless lead.tenant

      ContactMatch.apply(lead.tenant.leads.where.not(id: lead.id), lead,
        LeadSetting.instance(tenant: lead.tenant).stickiness_match)
    end

    def self.find_existing(lead)
      reference = event_reference(lead)
      received = find_received_event(tenant: lead.tenant, reference: reference) if reference
      return received if received

      if lead.business_scoped_user_id.present?
        existing = lead.tenant.leads.where.not(id: lead.id).find_by(business_scoped_user_id: lead.business_scoped_user_id)
        return existing if existing
      end
      matches(lead)&.order(:created_at, :id)&.first
    end

    def self.find_received_event(tenant:, reference:)
      return if reference.blank?

      provider, identifier = reference.split(":", 2)
      key = { "meta" => "meta_leadgen_id", "olx" => "portal_lead_id", "linkedin" => "linkedin_response_id", "tiktok" => "tiktok_lead_id" }[provider]
      original = if key
        tenant.leads.where("other_information ->> ? = ?", key, identifier).order(:id).first
      elsif provider == "c2s"
        tenant.leads.find_by(external_lead_id: identifier)
      elsif provider == "whatsapp"
        tenant.leads.where("other_information -> 'whatsapp_entry' ->> 'message_id' = ?", identifier).order(:id).first
      end
      return original if original

      lead_id = tenant.lead_activities.where(kind: "inquiry_complemented")
        .where("metadata ? 'ingress_reference'")
        .where("metadata ->> 'ingress_reference' = ?", reference).order(:id).pick(:lead_id)
      tenant.leads.find_by(id: lead_id) if lead_id
    end

    def self.event_reference(lead)
      info = lead.other_information.to_h
      {
        "meta" => info["meta_leadgen_id"], "olx" => info["portal_lead_id"],
        "linkedin" => info["linkedin_response_id"], "tiktok" => info["tiktok_lead_id"],
        "c2s" => lead.external_lead_id, "whatsapp" => info.dig("whatsapp_entry", "message_id")
      }.find { |_provider, id| id.present? }&.join(":")
    end

    def self.receive!(inquiry, distribution_rule: nil)
      raise ArgumentError, "A entrada deve ser um lead novo" unless inquiry.new_record?
      raise ArgumentError, "Conta obrigatória" unless inquiry.tenant

      Current.set(tenant: inquiry.tenant) do
        raise ActiveRecord::RecordInvalid, inquiry unless inquiry.valid?

        # ponytail: lock por conta; lock por identidade se o volume exigir maior concorrência.
        target = inquiry.tenant.with_lock do
          existing = find_existing(inquiry)
          unless existing
            inquiry.save!
            next inquiry
          end
          reference = event_reference(inquiry)
          already_received = reference && (event_reference(existing) == reference ||
            find_received_event(tenant: inquiry.tenant, reference: reference))
          unless already_received
            previous_assignment = existing.attributes.slice("admin_user_id", "status", "lead_pipeline_stage_id", "distribution_rule_id",
              "archived_at", "archive_reason_id", "archive_note")
            existing.skip_automatic_routing = true
            route = distribution_rule.present? || !inquiry.skip_automatic_routing?
            routing = DistributorService.redistribute(existing, inquiry: inquiry,
              rule: distribution_rule || inquiry.distribution_rule) if route
            InquiryComplement.complement!(existing, inquiry, notify: false,
              metadata: { "previous_assignment" => previous_assignment })
            if routing == :kept
              habitation = inquiry.property_id.present? ? existing.tenant.habitations.find_by(id: inquiry.property_id) : nil
              NotificationDispatcher.notify_complement(existing, habitation)
            end
            %i[external_lead_integration_id external_lead_id external_internal_id business_scoped_user_id].each do |field|
              existing[field] = inquiry[field] if existing[field].blank? && inquiry[field].present?
            end
            existing.other_information = existing.other_information.merge("intake_reconciled" => true)
            existing.save! if existing.changed?
            if route && previous_assignment["status"] != existing.status
              Automation::Dispatcher.dispatch(:lead_stage_changed, existing, source: "lead",
                payload: { from: previous_assignment["status"], to: existing.status })
            end
          end
          existing
        end
        target.intake_reused = target != inquiry
        target.skip_automatic_routing = false if target.intake_reused && !inquiry.skip_automatic_routing?
        target
      end
    end
  end
end
