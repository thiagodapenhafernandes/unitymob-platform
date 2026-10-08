module ExternalLeadMigration
  # Monta o payload de exportação de um lead local para o C2S, espelhando o
  # formato que a própria API devolve na leitura. O contrato de escrita ainda
  # não foi confirmado com o C2S: este mapeamento é o ponto único a ajustar
  # quando a documentação oficial chegar.
  class LeadExportMapper
    def self.call(lead:)
      new(lead:).call
    end

    def initialize(lead:)
      @lead = lead
    end

    def call
      {
        "customer" => customer_attributes,
        "description" => description,
        "observation" => observation,
        "lead_source" => { "name" => lead.origin.presence || "Unitymob" },
        "seller" => seller_attributes,
        "custom_attributes" => custom_attributes,
        "external_reference" => "unitymob:#{lead.tenant_id}:#{lead.id}"
      }.compact
    end

    private

    attr_reader :lead

    def customer_attributes
      {
        "name" => lead.display_name,
        "email" => lead.display_email.presence,
        "phone" => Phones::Normalizer.call(lead.display_phone).presence
      }.compact
    end

    def description
      property&.display_title.presence || lead.product.presence
    end

    def observation
      [
        lead.product.presence,
        ("Origem: #{lead.origin}" if lead.origin.present?),
        ("Página: #{lead.source_url}" if lead.source_url.present?)
      ].compact.join(" · ").presence
    end

    def seller_attributes
      owner = lead.admin_user
      return nil if owner.blank? || owner.tenant_id != lead.tenant_id

      { "email" => owner.email.presence, "name" => owner.name.presence }.compact.presence
    end

    def custom_attributes
      {
        "unitymob_lead_id" => lead.id,
        "unitymob_origin" => lead.origin,
        "unitymob_status" => lead.status,
        "unitymob_property_id" => property&.id,
        "unitymob_property_code" => property&.codigo
      }.compact
    end

    def property
      @property ||=
        if lead.property_id.present?
          lead.tenant.habitations.find_by(id: lead.property_id)
        end
    end
  end
end
