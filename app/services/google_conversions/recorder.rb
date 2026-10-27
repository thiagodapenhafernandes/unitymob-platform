module GoogleConversions
  class Recorder
    EVENTS = {
      "qualify_lead" => ["qualify_lead", "qualificado"],
      "visit" => ["working_lead", "visita"],
      "proposal" => ["working_lead", "proposta"],
      "closed" => ["close_convert_lead", "fechamento"]
    }.freeze

    def self.business_type(value)
      { "sale" => "venda", "venda" => "venda", "rent" => "aluguel", "rental" => "aluguel", "aluguel" => "aluguel" }[value.to_s]
    end

    def self.lead_updated(lead)
      Leads::StageConversionEvents.dispatch(lead, Leads::StageConversionEvents.lead_actions(lead), provider: :google, occurred_at: lead.updated_at)
    end

    def self.record(lead, setting, event, occurred_at: lead.updated_at)
      GoogleStageConversionEvent.transaction(requires_new: true) do
        type = lead.google_business_type.presence || business_type(lead.attribution_data.to_h["business_type"]) || business_type(lead.lead_pipeline&.kind)
        original = lead.lead_audit_logs.where(tenant_id: lead.tenant_id, action: "created").order(:id).first&.changeset.to_h
        email = (original.dig("email", "after").presence || original.dig("client_email", "after")).to_s.downcase.gsub(/\s/, "")
        reason = if type.blank?
          "business_type_missing"
        elsif !email.match?(URI::MailTo::EMAIL_REGEXP)
          "original_email_missing"
        end
        if type
          Lead.where(tenant_id: lead.tenant_id, id: lead.id, google_business_type: nil).update_all(google_business_type: type)
          type = Lead.where(tenant_id: lead.tenant_id, id: lead.id).pick(:google_business_type)
        end
        name = (original.dig("name", "after").presence || original.dig("client_name", "after")).to_s.downcase.gsub(/[^\p{L}\p{M}\s]/, "").squish
        first, last = name.split(" ", 2)
        phone = (original.dig("phone", "after").presence || original.dig("client_phone", "after")).to_s.gsub(/\D/, "")
        parsed_phone = Phonelib.parse("+#{phone}") if phone.present?
        event_name, suffix = EVENTS.fetch(event)
        identifier = "#{lead.id}_#{suffix}"
        payload = {
          event_name: event_name, business_type: type, transaction_id: identifier, event_id: identifier,
          conversion_datetime: occurred_at.in_time_zone("America/Sao_Paulo").strftime("%Y-%m-%d %H:%M:%S%:z"),
          event_timestamp: occurred_at.to_i, lead_id: lead.id.to_s,
          user_data: { email_address: email.presence, phone_number: parsed_phone&.valid? ? parsed_phone.full_e164 : nil,
            address: { first_name: first.presence, last_name: last.presence }.compact.presence }.compact,
          diagnostic: Rails.env.production? ? nil : true
        }.compact.merge(Leads::TrackingUid.payload(lead.attribution_data))
        if event == "closed" && lead.closing_commission_cents.present?
          payload[:value] = BigDecimal(lead.closing_commission_cents.to_s) / 100
          payload[:currency] = "BRL"
        end
        GoogleStageConversionEvent.where(tenant_id: lead.tenant_id).create_or_find_by!(lead_id: lead.id, conversion_type: suffix) do |record|
          record.webhook_setting = setting
          record.occurred_at = occurred_at
          record.destination_url = setting.google_destination_url
          record.payload = ActiveSupport::JSON.encode(payload.merge(value: payload[:value]&.to_f).compact)
          record.status = reason ? "skipped" : "pending"
          record.skip_reason = reason
        end
      end
    end
  end
end
