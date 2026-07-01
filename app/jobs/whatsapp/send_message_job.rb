module Whatsapp
  class SendMessageJob < ApplicationJob
    queue_as :default

    def self.dispatch(message_id, tenant_id:)
      if inline_dispatch?
        perform_now(message_id, tenant_id: tenant_id)
      else
        perform_later(message_id, tenant_id: tenant_id)
      end
    end

    def self.inline_dispatch?
      override = ENV["WHATSAPP_SEND_INLINE"].to_s.strip
      return ActiveModel::Type::Boolean.new.cast(override) if override.present?

      Rails.env.development?
    end

    def perform(message_id, tenant_id: nil)
      message = message_scope(tenant_id).find_by(id: message_id)
      return unless message&.outbound?

      conversation = message.whatsapp_conversation
      return unless message.tenant_id == conversation.tenant_id

      Current.set(tenant: conversation.tenant) do
        recipient = conversation.cloud_recipient # telefone ou BSUID
        return update_message_status!(message, status: "failed", error_message: "Conversa sem telefone ou BSUID") if recipient.blank?

        client = Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(conversation.tenant))

        result =
          if message.msg_type == "template" && message.template_name.present?
            client.send_template(to: recipient, name: message.template_name)
          elsif message.media?
            send_media_message(client, recipient, message)
          else
            client.send_text(to: recipient, body: message.body)
          end

        if result[:ok]
          update_message_status!(message, status: "sent", wa_message_id: result[:message_id], sent_at: Time.current, error_message: nil)
        else
          update_message_status!(message, status: "failed", error_message: result[:error].to_s.truncate(250))
        end
      end
    end

    private

    def message_scope(tenant_id)
      return WhatsappMessage.all if tenant_id.blank?

      tenant = Tenant.find_by(id: tenant_id)
      tenant ? tenant.whatsapp_messages : WhatsappMessage.none
    end

    def send_media_message(client, recipient, message)
      uploaded_media_id = nil

      if message.media_file.attached?
        media_validation = Whatsapp::MediaSupport.validation_for(message.media_file.blob)
        return media_validation unless media_validation[:ok]

        message.media_file.blob.open do |file|
          upload = client.upload_message_media(
            file_name: message.media_file.filename.to_s,
            content_type: media_validation[:content_type],
            type: media_validation[:type],
            io: file
          )
          return upload unless upload[:ok]

          uploaded_media_id = upload[:media_id]
        end
      end

      if uploaded_media_id.blank? && message.media_url.blank?
        return { ok: false, error: "Mídia sem arquivo anexado nem link remoto para envio." }
      end

      client.send_media(
        to: recipient,
        type: message.msg_type,
        media_id: uploaded_media_id,
        link: uploaded_media_id.present? ? nil : message.media_url,
        caption: message.body,
        filename: message.media_name
      )
    end

    def update_message_status!(message, attrs)
      message.update!(attrs)
      Whatsapp::ThreadBroadcaster.message_updated(message)
    end
  end
end
