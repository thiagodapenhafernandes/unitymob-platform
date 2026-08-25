module Whatsapp
  class ServiceWindowGuard
    Result = Struct.new(:locked?, :lead_name, :template_name, :message, :action_label, keyword_init: true)

    class << self
      def call(conversation:)
        new(conversation:).call
      end
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return unlocked unless conversation
      return unlocked unless activation_template_sent?
      return unlocked if inbound_after_activation?

      Result.new(
        locked?: true,
        lead_name: lead_name,
        template_name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        message: "Agora aguarde #{lead_name} responder para a conversa iniciar ou ser liberada.",
        action_label: "Reenviar apresentação oficial"
      )
    end

    private

    attr_reader :conversation

    def unlocked
      Result.new(locked?: false)
    end

    def activation_template_sent?
      last_activation_template_at.present?
    end

    def inbound_after_activation?
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
      @lead_name ||= conversation.lead&.display_name.presence || conversation.display_name.presence || "o lead"
    end
  end
end
