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
      attributes = {
        "name" => lead.display_name,
        "email" => lead.display_email.presence,
        "phone" => Phones::Normalizer.call(lead.display_phone).presence,
        "description" => (property&.display_title.presence || lead.product.presence)&.truncate(250),
        "prop_ref" => property&.codigo.presence || "Sem código",
        "observation" => [lead.product.presence, ("Origem: #{lead.origin}" if lead.origin.present?)].compact.join(" · ").presence,
        "url" => lead.source_url.presence,
        "source" => lead.origin.presence || "unitymob",
        "external_id" => "unitymob:#{lead.tenant_id}:#{lead.id}"
      }.compact
      raise ArgumentError, "C2S exige telefone ou e-mail" if attributes["phone"].blank? && attributes["email"].blank?

      { "data" => { "type" => "lead", "attributes" => attributes } }
    end

    private

    attr_reader :lead

    def property
      @property ||= lead.tenant.habitations.find_by(id: lead.property_id) if lead.property_id.present?
    end
  end
end
