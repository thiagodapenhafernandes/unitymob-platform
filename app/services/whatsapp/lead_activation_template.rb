module Whatsapp
  class LeadActivationTemplate
    TEMPLATE_NAME = "lead_activation_default_v2".freeze
    LANGUAGE = "pt_BR".freeze
    DEFAULT_BODY = "Oi! 👋 Aqui é {{1}}, da {{2}}. A partir de agora eu cuido do seu atendimento — pode falar comigo por aqui. Como posso ajudar?".freeze
    LEGACY_FIXED_FOOTER = "Atendimento Conexão".freeze
    DEFAULT_FOOTER = "Atendimento".freeze
    EDITABLE_STATUSES = ["", "DRAFT", "REJECTED"].freeze

    def self.for(tenant:, integration:)
      new(tenant:, integration:).template
    end

    def self.editable?(template)
      template.blank? || EDITABLE_STATUSES.include?(template.status.to_s.upcase)
    end

    def self.variable_values(lead:, admin_user:)
      {
        "1" => admin_user&.name.to_s.presence || "Corretor",
        "2" => lead.tenant&.name.to_s.presence || "imobiliária"
      }
    end

    def self.default_footer_for(tenant)
      DEFAULT_FOOTER
    end

    def initialize(tenant:, integration:)
      @tenant = tenant
      @integration = integration
    end

    def template
      @template ||= begin
        record = tenant.whatsapp_templates.find_or_initialize_by(
          name: TEMPLATE_NAME,
          language: LANGUAGE,
          waba_id: integration&.waba_id
        )
        apply_defaults(record)
        record
      end
    end

    private

    attr_reader :tenant, :integration

    def apply_defaults(record)
      record.template_type ||= "text"
      record.category ||= "MARKETING"
      record.status ||= "DRAFT"
      record.header_format ||= "image"
      record.body = DEFAULT_BODY if record.body.blank?
      if record.footer_text.blank? || (self.class.editable?(record) && record.footer_text == LEGACY_FIXED_FOOTER)
        record.footer_text = self.class.default_footer_for(tenant)
      end
      record.allow_category_change = true if record.allow_category_change.nil?
      record.example_values = ["Nome do corretor", "Nome da imobiliária"] if record.example_values.blank?
    end
  end
end
