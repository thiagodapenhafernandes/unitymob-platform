module Whatsapp
  class SendMessageJob < ApplicationJob
    queue_as :default

    def perform(message_id)
      message = WhatsappMessage.find_by(id: message_id)
      return unless message&.outbound?

      conversation = message.whatsapp_conversation
      client = Whatsapp::CloudClient.new

      result =
        if message.msg_type == "template" && message.template_name.present?
          client.send_template(to: conversation.contact_phone, name: message.template_name)
        else
          client.send_text(to: conversation.contact_phone, body: message.body)
        end

      if result[:ok]
        message.update!(status: "sent", wa_message_id: result[:message_id], sent_at: Time.current, error_message: nil)
      else
        message.update!(status: "failed", error_message: result[:error].to_s.truncate(250))
      end
    end
  end
end
