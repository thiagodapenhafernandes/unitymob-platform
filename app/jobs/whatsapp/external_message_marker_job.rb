module Whatsapp
  # A Meta só avisa (status "sent") de mensagens enviadas por outro sistema no mesmo número; o texto não vem.
  # Depois de uma carência — para não confundir com envio nosso ainda sem wamid gravado — registra no histórico
  # que houve uma mensagem por fora, para o time saber que alguém respondeu.
  class ExternalMessageMarkerJob < ApplicationJob
    queue_as :default

    LABEL = "Mensagem enviada por fora do sistema (o conteúdo não fica disponível aqui).".freeze

    def perform(tenant_id, wa_message_id, recipient_id, recipient_user_id, sent_at)
      tenant = Tenant.find_by(id: tenant_id)
      return if tenant.blank? || wa_message_id.blank?
      return if tenant.whatsapp_messages.exists?(wa_message_id: wa_message_id)
      return if LeadActivity.where(kind: "notification_sent").where("metadata ->> 'message_id' = ?", wa_message_id).exists?

      conversation = conversation_for(tenant, recipient_id, recipient_user_id)
      return if conversation.blank?

      at = (Time.zone.parse(sent_at.to_s) rescue nil) || Time.current
      message = conversation.messages.create!(
        tenant: tenant, direction: "outbound", msg_type: "external", status: "sent", wa_message_id: wa_message_id,
        body: LABEL, sent_at: at, created_at: at
      )
      conversation.touch_last_message!(message)
      Whatsapp::ThreadBroadcaster.message_created(message)
    rescue ActiveRecord::RecordNotUnique
      nil # outra entrega do mesmo aviso já registrou
    end

    private

    # Só vincula a conversas que já existem: nunca cria conversa a partir de um aviso de envio.
    def conversation_for(tenant, recipient_id, recipient_user_id)
      phone = Phones::Normalizer.call(recipient_id).to_s.presence
      (phone && tenant.whatsapp_conversations.find_by(contact_phone: phone)) ||
        (recipient_user_id.present? && tenant.whatsapp_conversations.find_by(business_scoped_user_id: recipient_user_id))
    end
  end
end
