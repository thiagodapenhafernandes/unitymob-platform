module Whatsapp
  class LeadAlertTemplate
    TEMPLATE_NAME = "lead_alert".freeze
    DISTRIBUTION_TEMPLATE_NAME = "lead_distribution_alert".freeze
    POOL_TEMPLATE_NAME = "lead_pool_alert".freeze
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
    DISTRIBUTION_BODY = <<~BODY.strip.freeze
      Novo lead no rodízio.

      *{{1}}*, você recebeu um lead pelo rodízio e tem até 10 minutos para atender.

      Detalhes do envio:
      • Nome: *{{3}}*
      • Origem: *{{2}}*
      • Telefone: *{{4}}*
      • Email: *{{5}}*
      • Outros dados: *{{6}}*

      Mensagem automática da plataforma.
    BODY
    POOL_BODY = <<~BODY.strip.freeze
      Lead disponível no bolsão.

      *{{1}}*, este lead está disponível para aceite no bolsão. Quem pegar primeiro assume o atendimento.

      Detalhes do envio:
      • Nome: *{{3}}*
      • Origem: *{{2}}*
      • Telefone/link: *{{4}}*
      • Email/link: *{{5}}*
      • Outros dados: *{{6}}*

      Mensagem automática da plataforma.
    BODY
    EXAMPLE_VALUES = ["Thiago", "Facebook", "Thiago", "21990872427", "iprodutora@gmail.com", "Form name"].freeze
    EDITABLE_STATUSES = ["", "DRAFT", "REJECTED"].freeze
    DEFINITIONS = {
      TEMPLATE_NAME => {
        label: "Aviso padrão legado",
        description: "Mantido para contas que já usam o template antigo de distribuição.",
        body: DEFAULT_BODY
      },
      DISTRIBUTION_TEMPLATE_NAME => {
        label: "Aviso de rodízio",
        description: "Enviado ao corretor quando o lead entra para ele pelo rodízio com prazo de atendimento.",
        body: DISTRIBUTION_BODY
      },
      POOL_TEMPLATE_NAME => {
        label: "Aviso de bolsão",
        description: "Enviado aos corretores quando o lead fica disponível no bolsão.",
        body: POOL_BODY
      }
    }.freeze

    def self.names
      DEFINITIONS.keys
    end

    def self.all(tenant:, integration:)
      names.map do |name|
        {
          name: name,
          definition: DEFINITIONS.fetch(name),
          template: self.for(tenant: tenant, integration: integration, name: name)
        }
      end
    end

    def self.for(tenant:, integration:, name: TEMPLATE_NAME)
      new(tenant:, integration:, name: name).template
    end

    def self.editable?(template)
      template.blank? || EDITABLE_STATUSES.include?(template.status.to_s.upcase)
    end

    def self.definition(name)
      DEFINITIONS.fetch(name.to_s, DEFINITIONS.fetch(TEMPLATE_NAME))
    end

    def initialize(tenant:, integration:, name: TEMPLATE_NAME)
      @tenant = tenant
      @integration = integration
      @name = DEFINITIONS.key?(name.to_s) ? name.to_s : TEMPLATE_NAME
      @definition = self.class.definition(@name)
    end

    def template
      @template ||= begin
        record = tenant.whatsapp_templates.find_or_initialize_by(
          name: name,
          language: LANGUAGE,
          waba_id: integration&.waba_id
        )
        apply_defaults(record)
        record
      end
    end

    private

    attr_reader :tenant, :integration, :name, :definition

    def apply_defaults(record)
      record.template_type ||= "text"
      record.category ||= "UTILITY"
      record.status ||= "DRAFT"
      record.header_format = "none"
      record.header_text = nil
      record.header_media_handle = nil
      record.body = definition.fetch(:body) if record.body.blank?
      record.footer_text = nil
      record.buttons = []
      record.carousel_cards = []
      record.flow_config = {}
      record.allow_category_change = true if record.allow_category_change.nil?
      record.example_values = EXAMPLE_VALUES if record.example_values.blank?
    end
  end
end
