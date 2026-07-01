module Whatsapp
  class ThreadContextSnapshot
    def initialize(conversation:, messages:, focus_mode:, tenant: nil)
      @conversation = conversation
      @messages = Array(messages)
      @focus_mode = focus_mode
      @tenant = tenant || conversation.tenant
    end

    def to_h
      {
        conversation: conversation,
        focus_mode: focus_mode,
        thread_lead: thread_lead,
        thread_property: thread_property,
        thread_next_task: thread_next_task,
        thread_summary: thread_summary,
        thread_actions_summary: thread_actions_summary
      }
    end

    private

    attr_reader :conversation, :messages, :focus_mode, :tenant

    def thread_lead
      @thread_lead ||= conversation.lead
    end

    def thread_property
      @thread_property ||= tenant&.habitations&.find_by(id: thread_lead&.property_id)
    end

    def thread_tasks
      @thread_tasks ||= thread_lead ? thread_lead.tasks.includes(:admin_user).ordered.limit(20).to_a : []
    end

    def thread_next_task
      @thread_next_task ||= thread_tasks.select(&:pendente?).find { |task| task.due_at.present? } || thread_tasks.find(&:pendente?)
    end

    def thread_summary
      @thread_summary ||= {
        pending_count: messages.count { |message| message.outbound? && message.status == "pending" },
        failed_count: messages.count { |message| message.outbound? && message.status == "failed" },
        media_count: messages.count(&:media?),
        last_activity_at: conversation.last_message_at || conversation.updated_at
      }
    end

    def thread_actions_summary
      @thread_actions_summary ||= if thread_lead
        {
          tasks: thread_lead.tasks.where(status: "pendente").count,
          appointments: thread_lead.appointments.count,
          proposals: thread_lead.proposals.count
        }
      else
        { tasks: 0, appointments: 0, proposals: 0 }
      end
    end
  end
end
