module Whatsapp
  class ResponseFlowRunner
    def self.call(conversation:, inbound_message:, raw_message:, campaign_message: nil, phone_number_id: nil)
      new(conversation:, inbound_message:, raw_message:, campaign_message:, phone_number_id:).call
    end

    def initialize(conversation:, inbound_message:, raw_message:, campaign_message: nil, phone_number_id: nil)
      @conversation = conversation
      @inbound_message = inbound_message
      @raw_message = raw_message.is_a?(Hash) ? raw_message.with_indifferent_access : {}.with_indifferent_access
      @campaign_message = campaign_message
      @phone_number_id = phone_number_id
    end

    ATTENDANCE_ACTIONS = %w[distribute_lead send_to_user].freeze

    def call
      return if campaign_message&.whatsapp_campaign&.response_decision_rows&.any?
      return handle_free_text unless button_text.present?
      return answer_switch if switch_answer?
      return if automation_answer? # resposta a uma pergunta de automação: quem trata é a própria automação

      flow = matching_flow
      return unless flow

      action = flow.action_for(button_key: button_key, button_text: button_text)
      return if action.blank?

      attendance = conversation.open_attendance
      return handle_click_during_attendance(attendance, flow) if attendance && ATTENDANCE_ACTIONS.include?(action["action"].to_s)

      run_action(flow, action)
    end

    private

    attr_reader :conversation, :inbound_message, :raw_message, :campaign_message, :phone_number_id

    def run_action(flow, action)
      inside_hours = flow.business_hours_active?(action)
      send_auto_reply(action, inside_hours)
      execute_action(flow, action)
      log_action(flow, action, inside_hours)
    end

    # Texto livre: com atendimento aberto vale a fidelização (e a checagem do dono);
    # sem atendimento aberto, depois de um encerrado, o menu volta como porta de entrada.
    def handle_free_text
      attendance = conversation.open_attendance
      if attendance
        AttendanceManager.ensure_owner_available!(attendance)
      elsif automation_waiting_for_answer?
        nil # o cliente está respondendo uma pergunta da automação: não devolve o menu
      else
        template = receptive_response_flow&.whatsapp_template || conversation.attendances.order(:closed_at).last&.whatsapp_response_flow&.whatsapp_template
        AttendanceManager.resend_menu!(conversation, template)
      end
    end

    def automation_waiting_for_answer?
      lead = conversation.context_lead
      lead.present? && AutomationExecution.where(tenant_id: conversation.tenant_id, lead_id: lead.id, status: "waiting").exists?
    end

    def handle_click_during_attendance(attendance, flow)
      if attendance.button_key == button_key
        AttendanceManager.send_text(conversation, "Você já tem um atendimento em andamento com #{attendance.owner&.name || 'nossa equipe'}. Aguarde o contato 😊")
      else
        AttendanceManager.request_switch!(attendance, flow: flow, button_key: button_key, button_text: button_text)
      end
    end

    def automation_answer?
      button_key.to_s.start_with?("aq:")
    end

    def switch_answer?
      button_key.to_s.start_with?("#{AttendanceManager::SWITCH_PREFIX}:")
    end

    def answer_switch
      _prefix, answer, attendance_id = button_key.split(":")
      attendance = conversation.attendances.open_now.find_by(id: attendance_id)
      pending = attendance&.pending_switch.to_h
      return if attendance.nil? || pending.blank?

      attendance.update!(pending_switch: {})
      if answer == "yes"
        AttendanceManager.close!(attendance, reason: "switched_by_customer")
        flow = conversation.tenant.whatsapp_response_flows.find_by(id: pending["flow_id"])
        action = flow&.action_for(button_key: pending["button_key"], button_text: pending["button_text"])
        run_action(flow, action) if action.present?
      else
        AttendanceManager.send_text(conversation, "Tudo bem! Seguimos com o seu atendimento atual. 😊")
      end
    end

    def matching_flow
      template = context_template
      return matching_context_flow(template) if template

      receptive_flow = receptive_response_flow
      return receptive_flow if receptive_flow&.action_for(button_key: button_key, button_text: button_text).present?

      conversation.tenant.whatsapp_response_flows.active.includes(:whatsapp_template).detect { |flow| flow.action_for(button_key: button_key, button_text: button_text).present? }
    end

    def matching_context_flow(template)
      scope = conversation.tenant.whatsapp_response_flows.active.includes(:whatsapp_template)
      scope = scope.where(whatsapp_template_id: template.id)
      scope.detect { |flow| flow.action_for(button_key: button_key, button_text: button_text).present? }
    end

    def receptive_response_flow
      return if phone_number_id.blank?

      conversation.tenant
                  .whatsapp_sender_numbers
                  .active
                  .includes(:receptive_response_flow)
                  .find_by(phone_number_id: phone_number_id)
                  &.receptive_response_flow
                  &.then { |flow| flow.active? ? flow : nil }
    end

    def context_template
      context_id = raw_message.dig(:context, :id).presence
      return if context_id.blank?

      outbound = conversation.tenant.whatsapp_messages.find_by(wa_message_id: context_id)
      return if outbound&.template_name.blank?

      conversation.tenant.whatsapp_templates.find_by(name: outbound.template_name)
    end

    def execute_action(flow, action)
      case action["action"].to_s
      when "create_task"
        create_task(action)
      when "run_automation"
        start_automation(action)
      when *ATTENDANCE_ACTIONS
        open_attendance(flow, action)
      end
    end

    # Enviar link: mensagem (opcional) + link, sem horário de atendimento.
    # Demais ações: sem horário vale a "Mensagem automática"; com horário, a "dentro do horário" (e a "fora" no resto).
    def send_auto_reply(action, inside_hours)
      return send_text_reply([action["message"].presence, action["url"].presence].compact.join("\n")) if action["action"].to_s == "send_url"

      hours_enabled = ActiveModel::Type::Boolean.new.cast(action.dig("business_hours", "enabled"))
      body =
        if !inside_hours
          action["outside_hours_message"].presence
        elsif hours_enabled
          action["inside_hours_message"].presence || action["message"].presence
        else
          action["message"].presence || action["inside_hours_message"].presence
        end
      send_text_reply(body)
    end

    def send_text_reply(body)
      return if body.blank?

      message = conversation.messages.create!(
        direction: "outbound",
        status: "pending",
        msg_type: "text",
        body: body
      )
      conversation.touch_last_message!(message)
      Whatsapp::ThreadBroadcaster.message_created(message)
      Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
    end

    # Cria a tarefa (tipo, prioridade e prazo vêm do botão; quem recebe é o corretor do lead), guarda o contexto do clique na
    # descrição e avisa a pessoa em tempo real. A confirmação ao cliente sai antes, por send_auto_reply.
    def create_task(action)
      lead = ensure_lead
      assignee = task_assignee(action, lead)
      unless assignee
        Rails.logger.warn("[ResponseFlow] tarefa não criada: sem responsável (conversa=#{conversation.id}, botão=#{button_text})")
        return
      end

      due_minutes = action["task_due_minutes"].to_i
      due_minutes = WhatsappResponseFlow::DEFAULT_TASK_DUE_MINUTES unless WhatsappResponseFlow::TASK_DUE_OPTIONS.key?(due_minutes)
      attrs = {
        tenant: conversation.tenant,
        # Tarefa com lead exige lead com corretor; sem corretor ela fica pessoal, com o contato na descrição.
        lead: (lead if lead&.admin_user_id.present?),
        admin_user: assignee,
        title: action["task_title"].presence || "Acompanhar resposta WhatsApp: #{button_text}",
        description: task_description(lead),
        kind: action["task_kind"].to_s.presence_in(Task::KINDS.keys) || "follow_up",
        status: "pendente",
        priority: action["task_priority"].to_s.presence_in(Task::PRIORITIES.keys) || "normal",
        due_at: due_minutes.minutes.from_now
      }
      attrs[:source] = "automation" if Task.column_names.include?("source")
      task = Task.create!(attrs)
      notify_task(task, assignee)
    end

    def task_assignee(action, lead)
      # Tarefa de um lead sempre segue o corretor dele (regra de Task). O usuário do botão só entra quando o lead ainda não tem corretor.
      lead&.admin_user || conversation.tenant.admin_users.active.find_by(id: action["task_user_id"].presence) || conversation.assigned_admin_user
    end

    def task_description(lead)
      contact = [lead&.name.presence || conversation.contact_name, conversation.contact_phone].compact_blank.join(" · ")
      ["O cliente clicou em “#{button_text}” no menu do WhatsApp.", ("Contato: #{contact}" if contact.present?)].compact.join("\n")
    end

    def notify_task(task, assignee)
      InAppNotification.notify!(
        admin_user: assignee, kind: "whatsapp_task", title: "Nova tarefa: #{task.title}",
        body: "Prazo: #{I18n.l(task.due_at, format: :short)}",
        url: Rails.application.routes.url_helpers.admin_whatsapp_conversation_path(conversation),
        metadata: { conversation_id: conversation.id, task_id: task.id }
      )
    end

    # Entrega a conversa a um fluxo do construtor de automações (perguntas, condições, passagem para atendente).
    def start_automation(action)
      workflow = conversation.tenant.automation_workflows.active.find_by(id: action["automation_workflow_id"])
      lead = ensure_lead
      return if workflow.blank? || lead.blank?

      # Cliente voltou ao menu: encerra a conversa automática anterior que ainda esperava resposta.
      previous = AutomationExecution.where(tenant_id: conversation.tenant_id, lead_id: lead.id, status: "waiting")
                                    .where(automation_event_id: conversation.tenant.automation_events.where(name: "whatsapp_flow_button").select(:id))
      previous.update_all(status: "canceled", updated_at: Time.current)

      event = conversation.tenant.automation_events.create!(
        name: "whatsapp_flow_button", lead: lead, source: "whatsapp", status: "processed", occurred_at: Time.current,
        payload: {
          conversation_id: conversation.id, inbound_whatsapp_message_id: inbound_message.id, whatsapp_message_id: inbound_message.id,
          button_text: button_text, button_payload: button_key, message_body: button_text
        }
      )
      Automation::WorkflowRunner.start(workflow, lead, event: "whatsapp_flow_button", automation_event: event)
    end

    def open_attendance(flow, action)
      lead = ensure_lead
      AttendanceManager.open!(conversation: conversation, lead: lead, flow: flow, action: action) if lead
    end

    def ensure_lead
      return conversation.lead if conversation.lead

      lead = conversation.tenant.leads.create!(
        name: conversation.contact_name.presence || "Contato WhatsApp #{conversation.contact_phone || conversation.business_scoped_user_id}",
        phone: conversation.contact_phone,
        business_scoped_user_id: conversation.business_scoped_user_id,
        origin: "whatsapp",
        status: Lead.default_status
      )
      conversation.update!(lead: lead)
      lead
    end

    def log_action(flow, action, inside_hours)
      return unless conversation.lead

      LeadActivity.log!(lead: conversation.lead, kind: "whatsapp_response_flow", metadata: {
        flow_id: flow.id,
        flow_name: flow.name,
        template_id: flow.whatsapp_template_id,
        button_key: button_key,
        button_text: button_text,
        action: action["action"],
        inside_hours: inside_hours
      }.compact)
    end

    def button_text
      @button_text ||= raw_message.dig(:button, :text).presence ||
        raw_message.dig(:interactive, :button_reply, :title).presence ||
        raw_message.dig(:interactive, :list_reply, :title).presence
    end

    def button_key
      @button_key ||= raw_message.dig(:button, :payload).presence ||
        raw_message.dig(:button, :id).presence ||
        raw_message.dig(:interactive, :button_reply, :id).presence ||
        raw_message.dig(:interactive, :list_reply, :id).presence
    end
  end
end
