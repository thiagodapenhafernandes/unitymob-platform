module Whatsapp
  class LeadWindowTemplateSelector
    Result = Struct.new(:template, :label, :reason, keyword_init: true)

    class << self
      def call(conversation:, admin_user: nil)
        new(conversation:, admin_user:).call
      end
    end

    def initialize(conversation:, admin_user: nil)
      @conversation = conversation
      @admin_user = admin_user
    end

    def call
      return Result.new unless conversation&.tenant

      appointment_template || task_template || followup_template || activation_template || Result.new
    end

    private

    attr_reader :conversation, :admin_user

    def lead
      conversation.lead
    end

    def integration
      @integration ||= WhatsappBusinessIntegration.current(conversation.tenant)
    end

    def appointment_template
      return unless lead && Whatsapp::LeadConversationTemplates.appointment_for(lead)

      approved_conversation_template("lead_appointment_reminder", "Usar lembrete de agenda", "Há uma agenda futura vinculada ao lead.")
    end

    def task_template
      return unless lead && Whatsapp::LeadConversationTemplates.task_for(lead)

      approved_conversation_template("lead_task_reminder", "Usar lembrete de tarefa", "Há uma tarefa pendente vinculada ao lead.")
    end

    def followup_template
      return unless conversation.messages.inbound.exists?

      approved_conversation_template("lead_followup", "Usar retomada de conversa", "Já existe histórico de conversa com este contato.")
    end

    def activation_template
      template = Whatsapp::LeadActivationTemplate.for(tenant: conversation.tenant, integration: integration)
      return unless template.persisted? && template.approved?

      Result.new(template:, label: "Usar apresentação oficial", reason: "Primeiro contato ou fallback oficial.")
    end

    def approved_conversation_template(name, label, reason)
      template = Whatsapp::LeadConversationTemplates.for(tenant: conversation.tenant, integration:, name:)
      return unless template.persisted? && template.approved?

      Result.new(template:, label:, reason:)
    end
  end
end
