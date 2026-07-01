module Whatsapp
  class MessageRenderContext
    GROUP_WINDOW = 10.minutes

    class << self
      def previous_message_for(message)
        return unless message&.whatsapp_conversation_id

        WhatsappMessage
          .where(whatsapp_conversation_id: message.whatsapp_conversation_id)
          .where("created_at < ? OR (created_at = ? AND id < ?)", message.created_at, message.created_at, message.id)
          .order(created_at: :desc, id: :desc)
          .first
      end

      def next_message_for(message)
        return unless message&.whatsapp_conversation_id

        WhatsappMessage
          .where(whatsapp_conversation_id: message.whatsapp_conversation_id)
          .where("created_at > ? OR (created_at = ? AND id > ?)", message.created_at, message.created_at, message.id)
          .order(created_at: :asc, id: :asc)
          .first
      end

      def grouped_with_previous?(message, previous_message)
        return false unless message && previous_message
        return false unless message.direction == previous_message.direction
        return false unless message.created_at.to_date == previous_message.created_at.to_date

        (message.created_at - previous_message.created_at) <= GROUP_WINDOW
      end

      def grouped_with_next?(message, next_message)
        return false unless message && next_message
        return false unless message.direction == next_message.direction
        return false unless message.created_at.to_date == next_message.created_at.to_date

        (next_message.created_at - message.created_at) <= GROUP_WINDOW
      end
    end
  end
end
