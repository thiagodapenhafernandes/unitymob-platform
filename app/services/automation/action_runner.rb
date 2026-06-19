module Automation
  # Executa as ações de uma regra sobre um lead. Suporta "esperar X dias" (nutrição),
  # agendando a continuação via solid_queue.
  class ActionRunner
    MAX_DEPTH = 3

    def self.run(rule, lead, from: 0)
      new(rule, lead).run(from)
    end

    def initialize(rule, lead)
      @rule = rule
      @lead = lead
      @log = []
    end

    def run(from = 0)
      Thread.current[:automation_depth] = (Thread.current[:automation_depth] || 0) + 1
      actions = @rule.action_list
      i = from
      scheduled = false

      while i < actions.size
        action = actions[i]
        if action[:type] == "wait"
          schedule_continuation(i + 1, action[:days].to_i)
          scheduled = true
          break
        end
        execute(action)
        i += 1
      end

      @rule.register_run! if from.zero?
      record_run(scheduled ? "scheduled" : "executed")
    rescue => e
      Rails.logger.error("[automation] #{e.class}: #{e.message}")
      record_run("error", error: e.message)
    ensure
      Thread.current[:automation_depth] = [Thread.current[:automation_depth].to_i - 1, 0].max
    end

    private

    def record_run(status, error: nil)
      AutomationRun.create!(
        automation_rule: @rule,
        lead: @lead,
        status: status,
        executed_at: Time.current,
        result: { actions: @log, error: error }.compact
      )
    end

    def execute(action)
      case action[:type]
      when "create_task"            then act_create_task(action)
      when "send_whatsapp"          then act_send_whatsapp(action, template: false)
      when "send_whatsapp_template" then act_send_whatsapp(action, template: true)
      when "move_stage"             then act_move_stage(action)
      when "assign_agent"           then act_assign_agent(action)
      when "add_note"               then act_add_note(action)
      end
      @log << @rule.action_label(action)
    end

    def act_create_task(a)
      assignee = @lead.admin_user || AdminUser.active.first
      return unless assignee

      task = Task.create!(
        lead: @lead,
        admin_user: assignee,
        title: a[:title].presence || "Follow-up automático",
        kind: "follow_up",
        due_at: (a[:due_in_hours].presence || 24).to_i.hours.from_now,
        status: "pendente"
      )
      LeadActivity.log!(lead: @lead, kind: "task_created", metadata: { task_id: task.id, title: task.title, by: "Automação" })
    end

    def act_send_whatsapp(a, template:)
      phone = normalized_phone
      return if phone.blank?

      conversation = WhatsappConversation.find_or_create_by!(contact_phone: phone) do |c|
        c.lead = @lead
        c.contact_name = @lead.display_name
      end
      conversation.update(lead: @lead) if conversation.lead_id.blank?

      message =
        if template
          conversation.messages.create!(direction: "outbound", status: "pending", msg_type: "template",
                                        template_name: a[:template], body: WhatsappTemplate.find_by(name: a[:template])&.body)
        else
          conversation.messages.create!(direction: "outbound", status: "pending", msg_type: "text", body: render_text(a[:message]))
        end

      conversation.touch_last_message!(message)
      Whatsapp::SendMessageJob.perform_later(message.id)
      LeadActivity.log!(lead: @lead, kind: "whatsapp_out", metadata: { body: message.preview, by: "Automação" })
    end

    def act_move_stage(a)
      to = a[:to].to_s
      return if to.blank?
      @lead.update(status: to)
      LeadActivity.log!(lead: @lead, kind: "status_change", metadata: { to: @lead.status, by: "Automação" })
    end

    def act_assign_agent(a)
      agent = AdminUser.find_by(id: a[:admin_user_id])
      @lead.update(admin_user: agent) if agent
    end

    def act_add_note(a)
      LeadActivity.log!(lead: @lead, kind: "note", metadata: { contact_kind: "automação", body: render_text(a[:body]) })
    end

    def schedule_continuation(next_index, days)
      days = 1 if days <= 0
      Automation::RunActionsJob.set(wait: days.days).perform_later(@rule.id, @lead&.id, next_index)
    end

    def render_text(text)
      text.to_s
          .gsub("{{nome}}", @lead.display_name.to_s)
          .gsub("{{corretor}}", @lead.admin_user&.name.to_s)
    end

    def normalized_phone
      digits = @lead.display_phone.to_s.gsub(/\D/, "")
      return "" if digits.blank?
      digits.length <= 11 ? "55#{digits}" : digits
    end
  end
end
