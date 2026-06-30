module Whatsapp
  class SendMessageJob < ApplicationJob
    queue_as :default

    def perform(message_id, tenant_id: nil)
      message = message_scope(tenant_id).find_by(id: message_id)
      return unless message&.outbound?

      conversation = message.whatsapp_conversation
      return unless message.tenant_id == conversation.tenant_id

      Current.set(tenant: conversation.tenant) do
        recipient = conversation.cloud_recipient # telefone ou BSUID
        return message.update!(status: "failed", error_message: "Conversa sem telefone ou BSUID") if recipient.blank?

        client = Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(conversation.tenant))

        result =
          if message.msg_type == "template" && message.template_name.present?
            client.send_template(to: recipient, name: message.template_name)
          else
            client.send_text(to: recipient, body: message.body)
          end

        if result[:ok]
          message.update!(status: "sent", wa_message_id: result[:message_id], sent_at: Time.current, error_message: nil)
        else
          message.update!(status: "failed", error_message: result[:error].to_s.truncate(250))
        end
      end
    end

    private

    def message_scope(tenant_id)
      return WhatsappMessage.all if tenant_id.blank?

      tenant = Tenant.find_by(id: tenant_id)
      tenant ? tenant.whatsapp_messages : WhatsappMessage.none
    end
  end
end
