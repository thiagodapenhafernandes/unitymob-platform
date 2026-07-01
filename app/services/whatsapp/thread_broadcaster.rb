module Whatsapp
  class ThreadBroadcaster
    class << self
      def stream_name(conversation, focus_mode: false)
        workspace = focus_mode ? "focus" : "default"
        "whatsapp_conversation:#{conversation.tenant_id}:#{conversation.id}:#{workspace}"
      end

      def message_created(message)
        conversation = message.whatsapp_conversation
        broadcast_to_workspaces(conversation) do |focus_mode|
          {
            messages: [serialize_message(conversation, message, focus_mode: focus_mode)],
            updates: affected_neighbor_updates(conversation, message, focus_mode: focus_mode),
            status_cursor: status_cursor_for(conversation),
            queue: serialize_conversation(conversation),
            context_fragments: context_fragments(conversation, focus_mode: focus_mode)
          }
        end
      end

      def message_updated(message)
        conversation = message.whatsapp_conversation
        broadcast_to_workspaces(conversation) do |focus_mode|
          {
            updates: [serialize_message(conversation, message, focus_mode: focus_mode)],
            status_cursor: status_cursor_for(conversation),
            context_fragments: context_fragments(conversation, focus_mode: focus_mode)
          }
        end
      end

      def queue_refreshed(conversation)
        broadcast_to_workspaces(conversation) do |focus_mode|
          {
            status_cursor: status_cursor_for(conversation),
            queue: serialize_conversation(conversation),
            context_fragments: context_fragments(conversation, focus_mode: focus_mode)
          }
        end
      end

      private

      def broadcast_to_workspaces(conversation)
        [false, true].each do |focus_mode|
          ActionCable.server.broadcast(
            stream_name(conversation, focus_mode: focus_mode),
            yield(focus_mode)
          )
        end
      end

      def serialize_message(conversation, message, focus_mode:)
        media_url = media_url_for(conversation, message)
        previous_message = Whatsapp::MessageRenderContext.previous_message_for(message)
        next_message = Whatsapp::MessageRenderContext.next_message_for(message)

        {
          id: message.id,
          direction: message.direction,
          body: message.body,
          type: message.msg_type,
          status: message.status,
          at: message.created_at.strftime("%H:%M"),
          template_name: message.template_name,
          media_url: media_url,
          media_name: message.media_name,
          html: Admin::WhatsappInboxController.render(
            partial: "admin/whatsapp_inbox/message_bubble",
            formats: [:html],
            locals: {
              message: message,
              media_url: media_url,
              previous_message: previous_message,
              next_message: next_message,
              compact_mode: compact_mode_for(focus_mode)
            }
          )
        }
      end

      def affected_neighbor_updates(conversation, message, focus_mode:)
        [Whatsapp::MessageRenderContext.previous_message_for(message),
         Whatsapp::MessageRenderContext.next_message_for(message)]
          .compact
          .uniq(&:id)
          .reject { |candidate| candidate.id == message.id }
          .map { |candidate| serialize_message(conversation, candidate, focus_mode: focus_mode) }
      end

      def serialize_conversation(conversation)
        {
          id: conversation.id,
          html: Admin::WhatsappInboxController.render(
            partial: "admin/whatsapp_inbox/conversation_item",
            formats: [:html],
            locals: { conv: conversation, active: false, focus_mode: false, compact_mode: true, lead_labels: [] }
          )
        }
      end

      def media_url_for(conversation, message)
        return Rails.application.routes.url_helpers.message_media_admin_whatsapp_conversation_path(conversation, message_id: message.id) if message.media?
        return Rails.application.routes.url_helpers.rails_blob_path(message.media_file, disposition: "inline") if message.media_file.attached?

        nil
      end

      def status_cursor_for(conversation)
        conversation.messages.maximum(:updated_at)&.iso8601(6)
      end

      def context_fragments(conversation, focus_mode:)
        snapshot = Whatsapp::ThreadContextSnapshot.new(
          conversation: conversation,
          messages: conversation.messages.ordered.to_a,
          focus_mode: focus_mode,
          tenant: conversation.tenant
        ).to_h

        {
          summary_html: Admin::WhatsappInboxController.render(
            partial: "admin/whatsapp_inbox/thread_context_summary",
            formats: [:html],
            locals: {
              conversation: snapshot[:conversation],
              thread_lead: snapshot[:thread_lead],
              thread_summary: snapshot[:thread_summary],
              thread_lead_labels: []
            }
          ),
          crm_copy_html: Admin::WhatsappInboxController.render(
            partial: "admin/whatsapp_inbox/thread_context_crm_toggle_copy",
            formats: [:html],
            locals: {
              focus_mode: snapshot[:focus_mode],
              thread_lead: snapshot[:thread_lead],
              thread_property: snapshot[:thread_property],
              thread_next_task: snapshot[:thread_next_task]
            }
          ),
          crm_badges_html: Admin::WhatsappInboxController.render(
            partial: "admin/whatsapp_inbox/thread_context_crm_toggle_badges",
            formats: [:html],
            locals: {
              thread_lead: snapshot[:thread_lead],
              thread_summary: snapshot[:thread_summary],
              thread_actions_summary: snapshot[:thread_actions_summary]
            }
          ),
          crm_summary_html: Admin::WhatsappInboxController.render(
            partial: "admin/whatsapp_inbox/thread_context_crm_summary",
            formats: [:html],
            locals: {
              thread_lead: snapshot[:thread_lead],
              thread_property: snapshot[:thread_property],
              thread_next_task: snapshot[:thread_next_task]
            }
          ),
          actions_metrics_html: Admin::WhatsappInboxController.render(
            partial: "admin/whatsapp_inbox/thread_context_actions_metrics",
            formats: [:html],
            locals: {
              thread_actions_summary: snapshot[:thread_actions_summary]
            }
          )
        }
      end

      def compact_mode_for(_focus_mode)
        true
      end
    end
  end
end
