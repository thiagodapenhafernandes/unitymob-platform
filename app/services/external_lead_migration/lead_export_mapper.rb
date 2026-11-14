module ExternalLeadMigration
  # Contrato POST /integration/leads: https://docs-api-leads.c2sapp.com/docs.html
  class LeadExportMapper
    def self.call(lead:)
      new(lead:).call
    end

    def initialize(lead:)
      @lead = lead
    end

    def call
      campaign = campaign_source?
      routing = lead.distribution_rule&.destination_c2s? ? lead.distribution_rule.c2s_routing_attributes(campaign: campaign) : {}
      source = routing["source"] || (campaign ? DistributionRule::C2S_DEFAULT_SOURCE : (lead.origin.presence || "unitymob"))
      attributes = {
        "name" => lead.display_name,
        "email" => lead.display_email.presence,
        "phone" => Phones::Normalizer.call(lead.display_phone).presence,
        "description" => (property&.display_title.presence || lead.product.presence)&.truncate(250),
        "prop_ref" => property&.codigo.presence || "Sem código",
        "observation" => [lead.product.presence, ("Origem: #{source}" if lead.origin.present? || campaign)].compact.join(" · ").presence,
        "url" => lead.source_url.presence,
        "source" => source,
        "external_id" => "unitymob:#{lead.tenant_id}:#{lead.id}"
      }.compact.merge(routing)
      raise ArgumentError, "C2S exige telefone ou e-mail" if attributes["phone"].blank? && attributes["email"].blank?

      { "data" => { "type" => "lead", "attributes" => attributes } }
    end

    private

    attr_reader :lead

    def campaign_source?
      return true if lead.origin == "whatsapp_campaign"
      rule = lead.distribution_rule
      return false unless rule&.source_whatsapp_campaign? && rule.destination_c2s?

      lead.tenant.whatsapp_campaign_messages.where(lead_id: lead.id, status: "replied").includes(:whatsapp_campaign).any? do |message|
        decision = message.whatsapp_campaign.response_decision_for(
          button_text: message.reply_button_text.presence || message.reply_body,
          button_payload: message.reply_button_payload).with_indifferent_access
        decision[:action] == "generate_lead" && decision[:distribution_rule_id].to_s == rule.id.to_s
      end
    end

    def property
      @property ||= lead.tenant.habitations.find_by(id: lead.property_id) if lead.property_id.present?
    end
  end
end
