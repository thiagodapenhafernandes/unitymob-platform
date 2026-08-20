module Whatsapp
  class LeadConversationTemplates
    LANGUAGE = "pt_BR".freeze
    EDITABLE_STATUSES = ["", "DRAFT", "REJECTED"].freeze
    DEFAULT_CONTEXT = "sua busca por imóvel".freeze

    Definition = Struct.new(:name, :label, :description, :category, :body, :example_values, :purpose, keyword_init: true)

    DEFINITIONS = [
      Definition.new(
        name: "lead_followup",
        label: "Retomada de conversa",
        description: "Retomada natural quando a janela expirou e não há agenda ou tarefa específica.",
        category: "MARKETING",
        purpose: :followup,
        body: "Oi, {{1}}! Aqui é {{2}}, da {{3}}. Estou retomando nosso atendimento sobre {{4}}. Posso te ajudar por aqui?",
        example_values: ["Maria", "Thiago", "Conexão Imobiliária", DEFAULT_CONTEXT]
      ),
      Definition.new(
        name: "lead_appointment_reminder",
        label: "Lembrete de agenda",
        description: "Lembrete para visita, reunião ou ligação agendada no lead.",
        category: "UTILITY",
        purpose: :appointment,
        body: "Oi, {{1}}! Aqui é {{2}}, da {{3}}. Passando para lembrar do nosso compromisso em {{4}}, sobre {{5}}. Se precisar ajustar algo, pode falar comigo por aqui.",
        example_values: ["Maria", "Thiago", "Conexão Imobiliária", "20/08 às 15:00", "visita ao imóvel"]
      ),
      Definition.new(
        name: "lead_task_reminder",
        label: "Lembrete de tarefa",
        description: "Retomada baseada em tarefa ou retorno combinado no lead.",
        category: "UTILITY",
        purpose: :task,
        body: "Oi, {{1}}! Aqui é {{2}}, da {{3}}. Estou retomando o atendimento conforme combinado: {{4}}. Quando puder, me responda por aqui.",
        example_values: ["Maria", "Thiago", "Conexão Imobiliária", "enviar os documentos da proposta"]
      )
    ].freeze

    class << self
      def all
        DEFINITIONS
      end

      def names
        DEFINITIONS.map(&:name)
      end

      def find(name)
        DEFINITIONS.find { |definition| definition.name == name.to_s }
      end

      def for(tenant:, integration:, name:)
        definition = find(name)
        raise ArgumentError, "Template oficial não encontrado." unless definition

        record = tenant.whatsapp_templates.find_or_initialize_by(
          name: definition.name,
          language: LANGUAGE,
          waba_id: integration&.waba_id
        )
        apply_defaults(record, definition)
        record
      end

      def editable?(template)
        template.blank? || EDITABLE_STATUSES.include?(template.status.to_s.upcase)
      end

      def apply_defaults(record, definition)
        record.template_type ||= "text"
        record.category ||= definition.category
        record.status ||= "DRAFT"
        record.header_format = "none"
        record.header_text = nil
        record.header_media_handle = nil
        record.footer_text = nil
        record.body = definition.body if record.body.blank?
        record.buttons = []
        record.carousel_cards = []
        record.flow_config = {}
        record.allow_category_change = true if record.allow_category_change.nil?
        record.example_values = definition.example_values if record.example_values.blank?
      end

      def variable_values(name:, conversation:, admin_user:)
        definition = find(name)
        lead = conversation&.lead
        values = base_values(lead, admin_user)

        case definition&.purpose
        when :appointment
          appointment = appointment_for(lead)
          values.merge(
            "4" => appointment_time_label(appointment),
            "5" => appointment_subject(appointment)
          )
        when :task
          values.merge("4" => task_subject(task_for(lead)))
        else
          values.merge("4" => followup_context(lead))
        end
      end

      def appointment_for(lead)
        return unless lead

        lead.appointments
            .where(status: "agendado")
            .where("starts_at >= ?", Time.current.beginning_of_day)
            .order(:starts_at)
            .first
      end

      def task_for(lead)
        return unless lead

        lead.tasks
            .where(status: "pendente")
            .order(Arel.sql("due_at ASC NULLS LAST, created_at DESC"))
            .first
      end

      private

      def base_values(lead, admin_user)
        {
          "1" => lead&.display_name.to_s.presence || "tudo bem",
          "2" => admin_user&.name.to_s.presence || lead&.admin_user&.name.to_s.presence || "Corretor",
          "3" => lead&.tenant&.name.to_s.presence || "imobiliária"
        }
      end

      def followup_context(lead)
        habitation = lead&.tenant&.habitations&.find_by(id: lead.property_id) if lead&.property_id.present?
        return habitation.display_title if habitation&.respond_to?(:display_title) && habitation.display_title.present?

        DEFAULT_CONTEXT
      end

      def appointment_time_label(appointment)
        return "data combinada" unless appointment&.starts_at

        I18n.l(appointment.starts_at, format: "%d/%m às %H:%M")
      end

      def appointment_subject(appointment)
        return "seu atendimento" unless appointment

        [appointment.kind_label, appointment.title].compact_blank.join(" - ").presence || "seu atendimento"
      end

      def task_subject(task)
        task&.title.to_s.presence || "dar sequência ao nosso atendimento"
      end
    end
  end
end
