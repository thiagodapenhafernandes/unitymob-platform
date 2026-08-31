module Whatsapp
  class ServiceWindowGuard
    Result = Struct.new(:locked?, :lead_name, :template_name, :message, :action_label, keyword_init: true)

    class << self
      def call(conversation:, admin_user: nil, lead: nil)
        new(conversation:, admin_user:, lead:).call
      end
    end

    def initialize(conversation:, admin_user: nil, lead: nil)
      @conversation = conversation
      @admin_user = admin_user
      @lead = lead
    end

    def call
      return unlocked unless conversation
      return unavailable unless integration_ready?
      return unlocked if free_entry_point_window_open?
      return unlocked if inbound_in_service_window?
      return unlocked if inbound_after_activation?

      template = Whatsapp::LeadWindowTemplateSelector.call(conversation:, admin_user:, lead:)

      Result.new(
        locked?: true,
        lead_name: lead_name,
        template_name: template.template&.name || Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        message: service_window_message,
        action_label: template.label.presence || "Enviar template aprovado"
      )
    end

    private

    SERVICE_WINDOW = 24.hours

    attr_reader :conversation, :admin_user, :lead

    def unlocked
      Result.new(locked?: false)
    end

    def unavailable
      Result.new(
        locked?: true,
        lead_name: lead_name,
        template_name: nil,
        message: "Integração WhatsApp não configurada para envio nesta conta.",
        action_label: "Configurar WhatsApp"
      )
    end

    def integration_ready?
      WhatsappBusinessIntegration.current(conversation.tenant).messaging_ready?
    end

    def inbound_in_service_window?
      conversation.messages.inbound.where("created_at >= ?", SERVICE_WINDOW.ago).exists?
    end

    def free_entry_point_window_open?
      conversation.free_entry_point_expires_at.present? && conversation.free_entry_point_expires_at.future?
    end

    def inbound_after_activation?
      return false unless last_activation_template_at

      conversation.messages.inbound.where("created_at > ?", last_activation_template_at).exists?
    end

    def last_activation_template_at
      @last_activation_template_at ||= conversation.messages.outbound
        .where(msg_type: "template", template_name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME)
        .where(status: %w[sent delivered read])
        .where.not(wa_message_id: nil)
        .maximum(:created_at)
    end

    def lead_name
      @lead_name ||= lead&.display_name.presence || conversation.lead&.display_name.presence || conversation.display_name.presence || "o lead"
    end

    def service_window_message
      if last_activation_template_at
        "Agora aguarde #{lead_name} responder para a conversa iniciar ou ser liberada."
      else
        "A janela de 24h do WhatsApp está fechada para #{lead_name}. Envie um template aprovado para ativar ou retomar o atendimento."
      end
    end
  end
end
