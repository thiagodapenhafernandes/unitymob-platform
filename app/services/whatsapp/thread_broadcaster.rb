module Whatsapp
  class ThreadBroadcaster
    class << self
      def stream_name(conversation, focus_mode: false)
        workspace = focus_mode ? "focus" : "default"
        "whatsapp_conversation:#{conversation.tenant_id}:#{conversation.id}:#{workspace}"
      end

      def message_created(message)
        conversation = message.whatsapp_conversation
        broadcast_to_workspaces(
          conversation,
          messages: [serialize_message(conversation, message)],
          updates: affected_neighbor_updates(conversation, message),
          status_cursor: status_cursor_for(conversation),
          queue: serialize_conversation(conversation)
        )
      end

      def message_updated(message)
        conversation = message.whatsapp_conversation
        broadcast_to_workspaces(
          conversation,
          updates: [serialize_message(conversation, message)],
          status_cursor: status_cursor_for(conversation)
        )
      end

      def queue_refreshed(conversation)
        broadcast_to_workspaces(
          conversation,
          status_cursor: status_cursor_for(conversation),
          queue: serialize_conversation(conversation)
        )
      end

      private

      # Payload computado UMA vez por evento: entre os 2 workspaces só o
      # crm_copy_html varia (focus_mode aparece apenas nesse partial; o
      # compact_mode dos bubbles é sempre true nos dois).
      def broadcast_to_workspaces(conversation, base_payload)
        snapshot = context_snapshot(conversation)
        shared_fragments = shared_context_fragments(snapshot)

        [false, true].each do |focus_mode|
          ActionCable.server.broadcast(
            stream_name(conversation, focus_mode: focus_mode),
            base_payload.merge(
              context_fragments: shared_fragments.merge(
                crm_copy_html: crm_copy_html(snapshot, focus_mode: focus_mode)
              )
            )
          )
        end
      end

      def serialize_message(conversation, message)
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
              compact_mode: true
            }
          )
        }
      end

      def affected_neighbor_updates(conversation, message)
        [Whatsapp::MessageRenderContext.previous_message_for(message),
         Whatsapp::MessageRenderContext.next_message_for(message)]
          .compact
          .uniq(&:id)
          .reject { |candidate| candidate.id == message.id }
          .map { |candidate| serialize_message(conversation, candidate) }
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

      def context_snapshot(conversation)
        Whatsapp::ThreadContextSnapshot.new(
          conversation: conversation,
          messages: [],
          focus_mode: false,
          tenant: conversation.tenant
        ).to_h.merge(thread_summary: thread_summary_counts(conversation))
      end

      # Contadores direto no banco — substitui o antigo messages.ordered.to_a
      # (histórico completo carregado por evento) com a mesma semântica.
      def thread_summary_counts(conversation)
        outbound_counts = conversation.messages.outbound.where(status: %w[pending failed]).reorder(nil).group(:status).count

        {
          pending_count: outbound_counts["pending"].to_i,
          failed_count: outbound_counts["failed"].to_i,
          media_count: conversation.messages.where(msg_type: %w[image document audio video]).count,
          last_activity_at: conversation.last_message_at || conversation.updated_at
        }
      end

      def shared_context_fragments(snapshot)
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

      def crm_copy_html(snapshot, focus_mode:)
        Admin::WhatsappInboxController.render(
          partial: "admin/whatsapp_inbox/thread_context_crm_toggle_copy",
          formats: [:html],
          locals: {
            focus_mode: focus_mode,
            thread_lead: snapshot[:thread_lead],
            thread_property: snapshot[:thread_property],
            thread_next_task: snapshot[:thread_next_task]
          }
        )
      end
    end
  end
end
