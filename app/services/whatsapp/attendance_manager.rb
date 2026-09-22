module Whatsapp
  # Ciclo de vida do atendimento aberto por botão de fluxo de resposta:
  # abrir (rodízio no pool) -> aceitar -> [transferir] -> finalizar.
  class AttendanceManager
    DEFAULT_FINISH_MESSAGE = "Atendimento finalizado! 😊 Obrigado pelo contato. Se precisar de algo, é só nos chamar.".freeze
    MENU_RESEND_COOLDOWN = 30.minutes
    HUMAN_CONVERSATION_WINDOW = 12.hours
    SWITCH_PREFIX = "attsw".freeze

    FinishResult = Struct.new(:ok?, :warning, keyword_init: true)

    class << self
      def open!(conversation:, lead:, flow:, action:)
        tenant = conversation.tenant
        rule, owner, pool = resolve(tenant, action)
        unless owner && assign(lead, rule, owner)
          # Sem atendente elegível (check-in, perfil, regra inativa): não deixa a falha silenciosa.
          LeadActivity.log!(lead: lead, kind: "whatsapp_attendance_unassigned", metadata: {
            button_text: action["button_text"], rule_name: rule&.name, reason: owner ? "assign_failed" : "no_eligible_agent"
          }.compact)
          return
        end

        attendance = conversation.attendances.create!(
          tenant: tenant, lead: lead, whatsapp_response_flow: flow, distribution_rule: rule, admin_user: owner,
          button_key: action["button_key"], button_text: action["button_text"], agent_ids: pool,
          finish_message: action["finish_message"], status: "open", opened_at: Time.current
        )
        conversation.update_column(:assigned_admin_user_id, owner.id)
        LeadActivity.log!(lead: lead, kind: "whatsapp_attendance_opened", metadata: { attendance_id: attendance.id, button_text: attendance.button_text, admin_user_id: owner.id, admin_user_name: owner.name })
        notify(owner, conversation, "Novo atendimento", "#{attendance.button_text} · #{conversation.display_name}")
        broadcast_change(conversation)
        schedule_acceptance(attendance)
        attendance
      rescue ActiveRecord::RecordNotUnique
        conversation.open_attendance
      end

      # Abrir a conversa ou responder já conta como aceite.
      def accept!(conversation, admin_user)
        attendance = conversation.open_attendance
        return unless attendance && !attendance.accepted? && attendance.admin_user_id == admin_user&.id

        attendance.update!(accepted_at: Time.current)
        broadcast_change(conversation)
      end

      # Repasse automático (dono indisponível ou que não aceitou): próximo do grupo, pelo rodízio.
      def reassign!(attendance, reason:)
        rule = attendance.distribution_rule
        return unless attendance.open? && rule

        new_owner = pick_agent(rule, attendance.agent_ids, exclude: [attendance.admin_user_id])
        switch_owner!(attendance, new_owner, reason: reason) if new_owner
      end

      # Transferência manual para um colega dos candidatos do atendimento.
      def transfer!(attendance, to:, by:)
        return unless attendance.open? && to && to.id != attendance.admin_user_id
        return unless attendance.transfer_candidates.exists?(id: to.id)

        switch_owner!(attendance, to, reason: "manual", by: by)
      end

      def switch_owner!(attendance, new_owner, reason:, by: nil)
        conversation = attendance.whatsapp_conversation
        return unless assign(conversation.lead, attendance.distribution_rule, new_owner)

        previous = attendance.admin_user
        attendance.update!(admin_user: new_owner, accepted_at: nil)
        conversation.update_column(:assigned_admin_user_id, new_owner.id)
        LeadActivity.log!(lead: conversation.lead, kind: "whatsapp_attendance_transferred", metadata: {
          attendance_id: attendance.id, reason: reason, by: by&.name, from_admin_user_name: previous&.name, admin_user_id: new_owner.id, admin_user_name: new_owner.name
        }.compact)
        notify(new_owner, conversation, "Atendimento transferido para você", "#{attendance.button_text} · #{conversation.display_name}#{" (por #{by.name})" if by}")
        notify(previous, conversation, "Atendimento transferido", "#{conversation.display_name} passou para #{new_owner.name}") if previous && previous.id != new_owner.id && previous.id != by&.id
        broadcast_change(conversation, previous, by)
        schedule_acceptance(attendance)
        attendance
      end

      # Checagem preguiçosa (quando o cliente escreve): dono inativo ou fora da regra passa o atendimento adiante.
      def ensure_owner_available!(attendance)
        owner = attendance.admin_user
        rule = attendance.distribution_rule
        available = owner&.active? && (rule.nil? || rule.candidates_filtered_by_checkin.exists?(admin_user_id: owner.id))
        reassign!(attendance, reason: "unavailable") unless available
      end

      def finish!(attendance, admin_user:)
        conversation = attendance.whatsapp_conversation
        warning = nil
        if Whatsapp::ServiceWindowGuard.call(conversation: conversation, admin_user: admin_user, lead: conversation.lead).locked?
          warning = "A janela de 24h está fechada: o atendimento foi finalizado sem enviar a mensagem de encerramento."
        else
          send_text(conversation, attendance.finish_message.presence || DEFAULT_FINISH_MESSAGE, admin_user: admin_user)
        end
        close!(attendance, reason: "finished", by: admin_user)
        FinishResult.new(ok?: true, warning: warning)
      end

      def close!(attendance, reason:, by: nil)
        attendance.update!(status: "closed", closed_at: Time.current, close_reason: reason, closed_by: by, pending_switch: {})
        LeadActivity.log!(lead: attendance.whatsapp_conversation.lead, kind: "whatsapp_attendance_finished", metadata: {
          attendance_id: attendance.id, button_text: attendance.button_text, reason: reason, by: by&.name
        })
        notify_owner_of_close(attendance, reason, by)
        broadcast_change(attendance.whatsapp_conversation, attendance.admin_user, by)
        attendance
      end

      # Janela de 24h do WhatsApp fechada sem resposta do cliente: o próprio prazo do canal libera o atendimento.
      def expire!(attendance)
        close!(attendance, reason: "window_expired")
      end

      # Cliente clicou em outro botão com atendimento aberto: pergunta Sim/Não antes de trocar.
      def request_switch!(attendance, flow:, button_key:, button_text:)
        conversation = attendance.whatsapp_conversation
        attendance.update!(pending_switch: { "flow_id" => flow.id, "button_key" => button_key, "button_text" => button_text })
        notify(attendance.admin_user, conversation, "Cliente quer trocar de assunto", "#{conversation.display_name} pediu: #{button_text}")
        send_interactive(
          conversation,
          "Você já tem um atendimento em andamento sobre “#{attendance.button_text}”. Deseja encerrá-lo e iniciar um novo sobre “#{button_text}”?",
          [{ "id" => "#{SWITCH_PREFIX}:yes:#{attendance.id}", "title" => "Sim" }, { "id" => "#{SWITCH_PREFIX}:no:#{attendance.id}", "title" => "Não" }]
        )
      end

      def send_text(conversation, body, admin_user: nil)
        message = conversation.messages.create!(direction: "outbound", status: "pending", msg_type: "text", body: body, admin_user: admin_user)
        dispatch(conversation, message)
      end

      # Porta de entrada de um novo atendimento: devolve o menu quando o cliente escreve sem atendimento aberto
      # (primeiro contato ou depois de finalizar). Não interrompe conversa em andamento com um atendente humano.
      def resend_menu!(conversation, template)
        return unless template&.approved? && template.variable_count.zero?
        last_closed_at = conversation.attendances.maximum(:closed_at)
        human_since = [last_closed_at, HUMAN_CONVERSATION_WINDOW.ago].compact.max
        return if conversation.messages.outbound.where.not(admin_user_id: nil).where("created_at > ?", human_since).exists?

        menu_since = [last_closed_at, MENU_RESEND_COOLDOWN.ago].compact.max
        return if conversation.messages.outbound.where(template_name: template.name).where.not(status: "failed").where("created_at > ?", menu_since).exists?

        components = Whatsapp::TemplateMessageComponents.call(template: template, variables: {}, client: Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(conversation.tenant)))
        return unless components.ok?

        message = conversation.messages.create!(direction: "outbound", status: "pending", msg_type: "template", template_name: template.name, body: template.body, template_components: components.components)
        dispatch(conversation, message)
      end

      private

      def resolve(tenant, action)
        if action["action"] == "send_to_user"
          owner = tenant.admin_users.active.find_by(id: action["target_user_id"])
          [nil, owner, [owner&.id].compact]
        else
          rule = tenant.distribution_rules.active.find_by(id: action["distribution_rule_id"])
          pool = Array(action["target_admin_user_ids"].presence || action["target_admin_user_id"]).compact_blank.map(&:to_i)
          [rule, (pick_agent(rule, pool) if rule), pool]
        end
      end

      # Rodízio dentro do pool: quem recebeu há mais tempo (nunca recebeu = primeiro).
      def pick_agent(rule, pool, exclude: [])
        candidates = rule.candidates_filtered_by_checkin
        candidates = candidates.where(admin_user_id: pool) if pool.present?
        candidates = candidates.where.not(admin_user_id: exclude) if exclude.compact.any?
        candidates.reorder(Arel.sql("distribution_rule_agents.last_lead_received_at ASC NULLS FIRST"), :position).first&.admin_user
      end

      def assign(lead, rule, owner)
        return unless lead

        if rule
          return unless Leads::DistributorService.distribute_to_agent(lead, rule, owner)

          rule.mark_agent_served!(owner.id)
        else
          lead.update!(admin_user: owner, status: :em_atendimento)
          lead.activities.create(kind: "distributed", metadata: { admin_user_id: owner.id, admin_user_name: owner.name, direct_attendance: true, source: "whatsapp_response_flow" })
        end
        true
      end

      # Prazo de aceite é configuração do próprio botão do fluxo (independente do bolsão/pocket da regra).
      def schedule_acceptance(attendance)
        minutes = accept_timeout_minutes(attendance)
        return unless minutes && attendance.distribution_rule

        Whatsapp::AttendanceAcceptanceJob.set(wait: minutes.minutes)
                                         .perform_later(attendance.id, attendance.admin_user_id, tenant_id: attendance.tenant_id)
      end

      def accept_timeout_minutes(attendance)
        action = attendance.whatsapp_response_flow&.button_actions.to_h[attendance.button_key].to_h
        minutes = action["accept_timeout_minutes"].to_i
        minutes if minutes.positive?
      end

      def notify_owner_of_close(attendance, reason, by)
        owner = attendance.admin_user
        return unless owner

        conversation = attendance.whatsapp_conversation
        case reason
        when "switched_by_customer" then notify(owner, conversation, "Atendimento encerrado", "#{conversation.display_name} iniciou outro assunto")
        when "window_expired" then notify(owner, conversation, "Atendimento encerrado", "#{conversation.display_name}: a janela de 24h do WhatsApp fechou")
        when "finished" then notify(owner, conversation, "Atendimento finalizado por #{by.name}", conversation.display_name) if by && by.id != owner.id
        end
      end

      # Tempo real: atualiza a fila, o painel de contexto e a tela de gestão de quem participa ou gerencia.
      # `visible` diz se a conversa continua acessível para cada destinatário (senão a lista a remove).
      def broadcast_change(conversation, *extra_users)
        conversation = WhatsappConversation.find(conversation.id)
        html = Whatsapp::ThreadBroadcaster.queue_item_html(conversation)
        change_recipients(conversation, extra_users).each do |user|
          visible = WhatsappConversation.visible_to(user).exists?(conversation.id)
          InAppNotification.broadcast_event!(user.id, event: "attendance_changed", conversation_id: conversation.id, visible: visible, html: (html if visible))
        end
      rescue => e
        Rails.logger.warn("[AttendanceManager] tempo real falhou conv=#{conversation&.id}: #{e.class}: #{e.message}")
      end

      # Gestores (escopo equipe/todos no atendimento). A lista é cara de calcular (perfis) e muda pouco: cache curto.
      def change_recipients(conversation, extra_users)
        tenant = conversation.tenant
        manager_ids = Rails.cache.fetch("wa_attendance_managers:#{tenant.id}", expires_in: 10.minutes) do
          tenant.admin_users.active.includes(:profile, :horizontal_profile).select do |user|
            user.can?(:view, :whatsapp_inbox) && (user.owns_all?(:whatsapp_inbox) || user.can_view_team?(:whatsapp_inbox))
          end.map(&:id)
        end
        managers = tenant.admin_users.active.where(id: manager_ids).to_a
        ([conversation.open_attendance&.admin_user] + extra_users + managers).compact.uniq
      end

      def notify(user, conversation, title, body)
        InAppNotification.notify!(admin_user: user, kind: "whatsapp_attendance", title: title, body: body,
                                  url: Rails.application.routes.url_helpers.admin_whatsapp_conversation_path(conversation),
                                  metadata: { conversation_id: conversation.id })
      end

      def send_interactive(conversation, body, buttons)
        message = conversation.messages.create!(direction: "outbound", status: "pending", msg_type: "interactive", body: body, template_components: buttons)
        dispatch(conversation, message)
      end

      def dispatch(conversation, message)
        conversation.touch_last_message!(message)
        Whatsapp::ThreadBroadcaster.message_created(message)
        Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
      end
    end
  end
end
