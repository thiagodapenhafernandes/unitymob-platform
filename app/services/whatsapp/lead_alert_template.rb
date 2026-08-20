module Whatsapp
  class LeadAlertTemplate
    TEMPLATE_NAME = "lead_alert".freeze
    LANGUAGE = "pt_BR".freeze
    DEFAULT_BODY = <<~BODY.strip.freeze
      Confirmação de recebimento de contato.

      O cliente *{{1}}* enviou um formulário através de *{{2}}*.

      Detalhes do envio:
      • Nome: *{{3}}*
      • Telefone: *{{4}}*
      • Email: *{{5}}*
      • Outros dados: *{{6}}*

      Mensagem gerada automaticamente em resposta ao envio do cliente.
    BODY
    EXAMPLE_VALUES = ["Thiago", "Facebook", "Thiago", "21990872427", "iprodutora@gmail.com", "Form name"].freeze
    EDITABLE_STATUSES = ["", "DRAFT", "REJECTED"].freeze

    def self.for(tenant:, integration:)
      new(tenant:, integration:).template
    end

    def self.editable?(template)
      template.blank? || EDITABLE_STATUSES.include?(template.status.to_s.upcase)
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
      record.category ||= "UTILITY"
      record.status ||= "DRAFT"
      record.header_format = "none"
      record.header_text = nil
      record.header_media_handle = nil
      record.body = DEFAULT_BODY if record.body.blank?
      record.footer_text = nil
      record.buttons = []
      record.carousel_cards = []
      record.flow_config = {}
      record.allow_category_change = true if record.allow_category_change.nil?
      record.example_values = EXAMPLE_VALUES if record.example_values.blank?
    end
  end
end
