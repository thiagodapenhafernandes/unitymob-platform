module Automation
  class ActionExecutor
    def self.execute(action, lead)
      new(lead).execute(action)
    end

    def self.label(action)
      action = action.with_indifferent_access

      case action[:type]
      when "create_task"            then "criar tarefa “#{action[:title]}”"
      when "send_whatsapp"          then "enviar WhatsApp"
      when "send_whatsapp_template" then "enviar modelo “#{action[:template]}”"
      when "send_webhook"           then "enviar webhook"
      when "set_flow_result"        then flow_result_label(action)
      when "move_stage"             then "mover para “#{action[:to]}”"
      when "update_lead_lifecycle"  then lifecycle_label(action)
      when "assign_agent"           then "ação vertical legada"
      when "add_note"               then "registrar nota"
      when "create_interest_curation_task" then "criar tarefa de curadoria"
      when "add_interest_note"      then "registrar interesse detectado"
      when "suggest_matching_properties" then "sugerir imóveis compatíveis"
      when "notify_broker_interest_opportunity" then "criar alerta para responsável do lead"
      when "prepare_matching_properties_whatsapp" then "preparar WhatsApp com imóveis"
      when "generate_interest_ai_summary" then "gerar resumo inteligente"
      when "wait"                   then "esperar #{action[:days]} dia(s)"
      else action[:type].to_s
      end
    end

    def initialize(lead, automation_event: nil)
      @lead = lead
      @automation_event = automation_event
    end

    def execute(action)
      action = action.with_indifferent_access

      case action[:type]
      when "create_task"            then act_create_task(action)
      when "send_whatsapp"          then act_send_whatsapp(action, template: false)
      when "send_whatsapp_template" then act_send_whatsapp(action, template: true)
      when "send_webhook"           then act_send_webhook(action)
      when "set_flow_result"        then act_set_flow_result(action)
      when "move_stage"             then act_move_stage(action)
      when "update_lead_lifecycle"  then act_update_lead_lifecycle(action)
      when "assign_agent"           then act_assign_agent(action)
      when "add_note"               then act_add_note(action)
      when "create_interest_curation_task" then act_create_interest_curation_task(action)
      when "add_interest_note"      then act_add_interest_note(action)
      when "suggest_matching_properties" then act_suggest_matching_properties(action)
      when "notify_broker_interest_opportunity" then act_notify_broker_interest_opportunity(action)
      when "prepare_matching_properties_whatsapp" then act_prepare_matching_properties_whatsapp(action)
      when "generate_interest_ai_summary" then act_generate_interest_ai_summary(action)
      end
    end

    private

    def self.lifecycle_label(action)
      labels = {
        "mark_no_interest" => "marcar sem interesse",
        "remove_no_interest" => "remover sem interesse",
        "block_lead" => "bloquear lead",
        "discard_lead" => "descartar lead",
        "unsubscribe_lead" => "descadastrar lead",
        "reactivate_lead" => "reativar lead"
      }
      labels[action[:lifecycle_action].to_s] || "atualizar ciclo de vida"
    end

    def self.flow_result_label(action)
      if action[:result].to_s == "generates_attendance"
        "resultado: gera atendimento"
      elsif action[:result].to_s == "record_only"
        "resultado: apenas registrar"
      else
        "resultado: não gera atendimento"
      end
    end

    def act_create_task(action)
      assignee = task_assignee(action)
      return unless assignee

      task = Task.create!(
        tenant: @lead.tenant,
        lead: @lead,
        admin_user: assignee,
        title: action[:title].presence || "Follow-up automático",
        kind: "follow_up",
        due_at: (action[:due_in_hours].presence || 24).to_i.hours.from_now,
        status: "pendente"
      )
      LeadActivity.log!(lead: @lead, kind: "task_created", metadata: { task_id: task.id, title: task.title, by: "Automação" })
    end

    def act_send_whatsapp(action, template:)
      phone = normalized_phone
      return if phone.blank?

      conversation = @lead.tenant.whatsapp_conversations.find_or_create_by!(contact_phone: phone) do |record|
        record.lead = @lead
        record.contact_name = @lead.display_name
      end
      conversation.update(lead: @lead) if conversation.lead_id.blank?

      message =
        if template
          conversation.messages.create!(
            direction: "outbound",
            status: "pending",
            msg_type: "template",
            template_name: action[:template],
            body: @lead.tenant.whatsapp_templates.find_by(name: action[:template])&.body
          )
        else
          conversation.messages.create!(
            direction: "outbound",
            status: "pending",
            msg_type: "text",
            body: render_text(action[:message])
          )
        end

      conversation.touch_last_message!(message)
      Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
      LeadActivity.log!(lead: @lead, kind: "whatsapp_out", metadata: { body: message.preview, by: "Automação" })
    end

    def act_send_webhook(action)
      url = action[:url].to_s.strip
      return if url.blank?

      delivery = AutomationWebhookDelivery.create!(
        automation_event: @automation_event,
        lead: @lead,
        url: url,
        http_method: action[:http_method].presence || "post",
        request_headers: parse_headers(action[:headers]),
        request_payload: webhook_payload(action)
      )
      Automation::WebhookDeliveryJob.perform_later(delivery.id)
      if @lead
        LeadActivity.log!(
          lead: @lead,
          kind: "automation_webhook",
          metadata: { automation_webhook_delivery_id: delivery.id, url: url, event: @automation_event&.name }
        )
      end
    end

    def act_set_flow_result(action)
      result = action[:result].presence || "no_attendance"
      raise ArgumentError, "Resultado do caminho inválido" unless %w[generates_attendance no_attendance record_only].include?(result.to_s)

      destination = nil
      if result.to_s == "generates_attendance"
        destination = tenant.distribution_rules.active.find_by(id: action[:distribution_rule_id])
        raise ArgumentError, "Resultado com atendimento sem destino" unless destination

        @lead ||= campaign_recipient&.convert_to_lead!(distribution_rule: destination)
        raise ArgumentError, "Resultado com atendimento sem destinatário para converter" unless @lead

        @lead.update!(distribution_rule: destination)
      elsif @lead.nil? && campaign_recipient
        if result.to_s == "no_attendance"
          campaign_recipient.mark_no_interest!
        elsif campaign_recipient.conversion_status == "pending"
          campaign_recipient.update!(conversion_status: "ignored")
        end
      end

      if @lead
        LeadActivity.log!(
          lead: @lead,
          kind: "automation_flow_result",
          metadata: {
            result: result,
            result_label: flow_result_name(result),
            distribution_rule_id: destination&.id,
            distribution_rule_name: destination&.name,
            note: render_text(action[:note]),
            by: "Automação"
          }.compact
        )
      end
    end

    def act_move_stage(action)
      to = action[:to].to_s
      return if to.blank?
      raise ArgumentError, Automation::StagePolicy.blocked_stage_message(to) unless Automation::StagePolicy.allowed_transition?(to)

      @lead.update(status: to)
      LeadActivity.log!(lead: @lead, kind: "status_change", metadata: { to: @lead.status, by: "Automação" })
    end

    def act_update_lead_lifecycle(action)
      lifecycle_action = action[:lifecycle_action].to_s
      if @lead.nil? && campaign_recipient
        case lifecycle_action
        when "unsubscribe_lead"
          campaign_recipient.unsubscribe!
          register_campaign_unsubscribe!
        when "mark_no_interest", "block_lead", "discard_lead"
          campaign_recipient.mark_no_interest!
        end
        return
      end

      to = action[:to].presence || default_lifecycle_stage(lifecycle_action)
      raise ArgumentError, "Ação de ciclo de vida sem etapa de destino" if to.blank?
      raise ArgumentError, Automation::StagePolicy.blocked_stage_message(to) unless Automation::StagePolicy.allowed_transition?(to)

      from = @lead.status
      @lead.update!(status: to)
      LeadActivity.log!(
        lead: @lead,
        kind: "status_change",
        metadata: {
          from: from,
          to: @lead.status,
          lifecycle_action: lifecycle_action,
          note: render_text(action[:note]),
          by: "Automação"
        }.compact
      )
    end

    def default_lifecycle_stage(lifecycle_action)
      case lifecycle_action.to_s
      when "mark_no_interest", "block_lead", "discard_lead"
        "Descartado"
      when "unsubscribe_lead"
        "Descadastrado"
      when "remove_no_interest", "reactivate_lead"
        "Em Atendimento"
      end
    end

    def flow_result_name(result)
      {
        "generates_attendance" => "Gera atendimento",
        "no_attendance" => "Não gera atendimento",
        "record_only" => "Apenas registrar"
      }[result.to_s] || result.to_s
    end

    def register_campaign_unsubscribe!
      message = webhook_campaign_message
      campaign = message&.whatsapp_campaign || webhook_campaign
      sender_number = campaign&.sender_number
      recipient = campaign_recipient
      return unless sender_number && message

      WhatsappCampaignUnsubscribe.register!(
        sender_number: sender_number,
        phone: message.phone_number,
        contact_name: recipient&.display_name,
        campaign_message: message,
        campaign_recipient: recipient,
        inbound_message: inbound_whatsapp_message,
        metadata: {
          automation_event_id: @automation_event&.id,
          automation_workflow: true
        }.compact
      )
    end

    def act_assign_agent(action)
      agent = @lead.tenant.admin_users.find_by(id: action[:admin_user_id])
      @lead.update(admin_user: agent) if agent
    end

    def act_add_note(action)
      LeadActivity.log!(lead: @lead, kind: "note", metadata: { contact_kind: "automação", body: render_text(action[:body]) })
    end

    def act_create_interest_curation_task(action)
      assignee = task_assignee(action)
      return unless assignee

      profile = InterestIntelligence::ProfileBuilder.call(@lead)
      task = Task.create!(
        tenant: @lead.tenant,
        lead: @lead,
        admin_user: assignee,
        title: action[:title].presence || "Curar imóveis para #{ @lead.display_name }",
        kind: "follow_up",
        due_at: (action[:due_in_hours].presence || 4).to_i.hours.from_now,
        status: "pendente",
        description: render_text(action[:notes].presence || interest_profile_text(profile))
      )
      LeadActivity.log!(lead: @lead, kind: "task_created", metadata: { task_id: task.id, title: task.title, by: "Inteligência de Interesse" })
    end

    def act_add_interest_note(action)
      profile = InterestIntelligence::ProfileBuilder.call(@lead)
      LeadActivity.log!(
        lead: @lead,
        kind: "note",
        metadata: {
          contact_kind: "inteligência de interesse",
          body: render_text(action[:body].presence || interest_profile_text(profile)),
          profile: profile
        }
      )
    end

    def act_suggest_matching_properties(action)
      matches = InterestIntelligence::Matcher.call(@lead, limit: action[:limit].presence&.to_i || 5)
      body = if matches.any?
               lines = matches.map do |result|
                 property = result.habitation
                 "- ##{property.codigo} #{property.display_title} (#{result.score} pontos: #{result.reasons.join(', ')})"
               end
               "Imóveis compatíveis encontrados:\n#{lines.join("\n")}"
             else
               "Nenhum imóvel compatível encontrado com os critérios atuais do lead."
             end

      LeadActivity.log!(
        lead: @lead,
        kind: "note",
        metadata: {
          contact_kind: "inteligência de interesse",
          body: body,
          matches: matches.map { |result| { habitation_id: result.habitation.id, score: result.score, reasons: result.reasons } }
        }
      )
    end

    def act_notify_broker_interest_opportunity(action)
      assignee = task_assignee(action)
      return unless assignee

      matches = InterestIntelligence::Matcher.call(@lead, limit: 3)
      summary = InterestIntelligence::AiSummary.call(@lead, matches: matches)
      task = Task.create!(
        tenant: @lead.tenant,
        lead: @lead,
        admin_user: assignee,
        title: action[:title].presence || "Oportunidade de interesse para #{@lead.display_name}",
        kind: "follow_up",
        due_at: (action[:due_in_hours].presence || 2).to_i.hours.from_now,
        status: "pendente",
        description: [summary["summary"], summary["broker_message"], matching_properties_text(matches)].compact_blank.join("\n\n")
      )

      LeadActivity.log!(lead: @lead, kind: "task_created", metadata: { task_id: task.id, title: task.title, by: "Inteligência de Interesse" })
    end

    def task_assignee(action)
      @lead.admin_user || fallback_admin_user(action) || tenant.admin_users.active.first
    end

    def fallback_admin_user(action)
      id = action[:fallback_admin_user_id].presence
      return nil if id.blank?

      tenant.admin_users.active.find_by(id: id)
    end

    def tenant
      @tenant ||= @lead&.tenant || campaign_recipient&.tenant || @automation_event&.tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para executar ação de automação" if @tenant.blank?

      @tenant
    end

    def act_prepare_matching_properties_whatsapp(action)
      settings = InterestIntelligence::Settings.current
      matches = InterestIntelligence::Matcher.call(@lead, limit: action[:limit].presence&.to_i || settings["max_suggestions"].to_i)
      summary = InterestIntelligence::AiSummary.call(@lead, matches: matches)
      message = [render_text(action[:message_prefix]), summary["lead_message"], matching_properties_public_text(matches)].compact_blank.join("\n\n")

      if settings.enabled_value?("allow_direct_lead_message") && !settings.enabled_value?("broker_review_required")
        act_send_whatsapp({ message: message }, template: false)
      else
        LeadActivity.log!(
          lead: @lead,
          kind: "note",
          metadata: {
            contact_kind: "rascunho WhatsApp",
            body: message,
            ai_summary: summary,
            matches: matches.map { |result| { habitation_id: result.habitation.id, score: result.score, reasons: result.reasons } }
          }
        )
        act_create_task(
          title: "Revisar WhatsApp com imóveis sugeridos",
          due_in_hours: 2,
          fallback_admin_user_id: action[:fallback_admin_user_id]
        )
      end
    end

    def act_generate_interest_ai_summary(action)
      matches = InterestIntelligence::Matcher.call(@lead)
      summary = InterestIntelligence::AiSummary.call(@lead, matches: matches)
      body = [
        "Classificação: #{summary['classification']}",
        summary["summary"],
        summary["broker_message"],
        (summary["lead_message"] if ActiveModel::Type::Boolean.new.cast(action[:include_lead_message])),
        Array(summary["rationale"]).map { |item| "- #{item}" }.join("\n")
      ].compact_blank.join("\n\n")

      LeadActivity.log!(
        lead: @lead,
        kind: "note",
        metadata: {
          contact_kind: "resumo inteligente",
          body: body,
          ai_summary: summary
        }
      )
    end

    def render_text(text)
      recipient = campaign_recipient
      text.to_s
          .gsub("{{nome}}", @lead&.display_name.to_s.presence || recipient&.display_name.to_s)
          .gsub("{{corretor}}", @lead&.admin_user&.name.to_s.presence || recipient&.admin_user&.name.to_s)
          .gsub("{{telefone}}", @lead&.display_phone.to_s.presence || recipient&.display_phone.to_s)
          .gsub("{{email}}", @lead&.display_email.to_s.presence || recipient&.display_email.to_s)
          .gsub("{{origem}}", @lead&.origin.to_s.presence || recipient&.origin.to_s)
    end

    def webhook_payload(action)
      template = action[:payload_template].to_s.strip
      if template.present?
        rendered = render_webhook_template(template)
        parsed = JSON.parse(rendered)
        return parsed if parsed.is_a?(Hash)
      end

      {
        event: @automation_event&.name,
        source: @automation_event&.source,
        occurred_at: @automation_event&.occurred_at&.iso8601,
        lead: webhook_lead_payload,
        recipient: webhook_recipient_payload,
        campaign: webhook_campaign_payload,
        campaign_message: webhook_campaign_message_payload,
        payload: @automation_event&.payload_hash || {}
      }.compact
    rescue JSON::ParserError
      { raw: render_webhook_template(template), lead_id: @lead&.id, event: @automation_event&.name }.compact
    end

    def render_webhook_template(template)
      rendered = render_text(template)

      rendered.gsub(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/) do
        token = Regexp.last_match(1)
        value = resolve_webhook_token(token)
        value.nil? ? "" : value.to_s
      end
    end

    def parse_headers(value)
      return value.to_h if value.is_a?(Hash)

      value.to_s.lines.each_with_object({}) do |line, memo|
        key, header_value = line.split(":", 2).map { |part| part.to_s.strip }
        memo[key] = render_webhook_template(header_value) if key.present? && header_value.present?
      end
    end

    def dig_hash(hash, dotted_key)
      dotted_key.to_s.split(".").reduce(hash.to_h.with_indifferent_access) do |memo, key|
        return nil unless memo.respond_to?(:[])

        memo[key]
      end
    end

    def resolve_webhook_token(token)
      context = webhook_context
      value = dig_hash(context, token)
      return value unless value.nil?

      if token.to_s.start_with?("event.")
        return dig_hash(@automation_event&.payload_hash || {}, token.to_s.delete_prefix("event."))
      end

      nil
    end

    def webhook_context
      lead_context = @lead && {
        "id" => @lead.id,
        "name" => @lead.display_name,
        "email" => @lead.display_email,
        "phone" => @lead.display_phone,
        "origin" => @lead.origin,
        "status" => @lead.status
      }
      agent_context = @lead && {
        "id" => @lead.admin_user_id,
        "name" => @lead.admin_user&.name,
        "email" => @lead.admin_user&.email
      }

      {
        "event" => {
          "id" => @automation_event&.id,
          "name" => @automation_event&.name,
          "source" => @automation_event&.source,
          "occurred_at" => @automation_event&.occurred_at&.iso8601,
          "payload" => @automation_event&.payload_hash || {}
        },
        "lead" => lead_context || {},
        "recipient" => webhook_recipient_payload || {},
        "agent" => agent_context || {},
        "whatsapp" => webhook_whatsapp_payload,
        "campaign" => webhook_campaign_payload || {},
        "campaign_message" => webhook_campaign_message_payload || {}
      }
    end

    def webhook_lead_payload
      return unless @lead

      {
        id: @lead.id,
        name: @lead.display_name,
        email: @lead.display_email,
        phone: @lead.display_phone,
        origin: @lead.origin,
        status: @lead.status,
        admin_user_id: @lead.admin_user_id,
        admin_user_name: @lead.admin_user&.name
      }
    end

    def webhook_recipient_payload
      recipient = campaign_recipient
      return unless recipient

      {
        id: recipient.id,
        lead_id: recipient.lead_id,
        name: recipient.display_name,
        email: recipient.display_email,
        phone: recipient.display_phone,
        origin: recipient.origin,
        status: recipient.status,
        conversion_status: recipient.conversion_status,
        tags: recipient.tag_list
      }
    end

    def campaign_recipient
      @campaign_recipient ||= begin
        payload = @automation_event&.payload_hash || {}
        id = payload[:whatsapp_campaign_recipient_id] || payload["whatsapp_campaign_recipient_id"]
        @automation_event.tenant.whatsapp_campaign_recipients.find_by(id: id) if id.present? && @automation_event&.tenant
      end
    end

    def webhook_whatsapp_payload
      payload = @automation_event&.payload_hash || {}
      message_id = payload[:whatsapp_message_id] || payload["whatsapp_message_id"] || payload[:inbound_whatsapp_message_id] || payload["inbound_whatsapp_message_id"]
      message = @automation_event.tenant.whatsapp_messages.find_by(id: message_id) if message_id.present? && @automation_event&.tenant

      {
        "message_id" => message&.id || message_id,
        "external_message_id" => message&.wa_message_id || payload[:wa_message_id] || payload["wa_message_id"],
        "phone" => payload[:phone] || payload["phone"] || message&.whatsapp_conversation&.contact_phone,
        "bsuid" => payload[:bsuid] || payload["bsuid"] || message&.whatsapp_conversation&.business_scoped_user_id,
        "message_body" => message&.body
      }.compact
    end

    def webhook_campaign
      @webhook_campaign ||= begin
        id = @automation_event&.payload_hash&.dig(:whatsapp_campaign_id) || @automation_event&.payload_hash&.dig("whatsapp_campaign_id")
        @automation_event.tenant.whatsapp_campaigns.find_by(id: id) if id.present? && @automation_event&.tenant
      end
    end

    def webhook_campaign_message
      @webhook_campaign_message ||= begin
        id = @automation_event&.payload_hash&.dig(:whatsapp_campaign_message_id) || @automation_event&.payload_hash&.dig("whatsapp_campaign_message_id")
        @automation_event.tenant.whatsapp_campaign_messages.find_by(id: id) if id.present? && @automation_event&.tenant
      end
    end

    def inbound_whatsapp_message
      payload = @automation_event&.payload_hash || {}
      id = payload[:inbound_whatsapp_message_id] || payload["inbound_whatsapp_message_id"] || payload[:whatsapp_message_id] || payload["whatsapp_message_id"]
      @automation_event.tenant.whatsapp_messages.find_by(id: id) if id.present? && @automation_event&.tenant
    end

    def webhook_campaign_payload
      campaign = webhook_campaign
      return nil unless campaign

      campaign.metrics_payload.merge(
        id: campaign.id,
        template: campaign.whatsapp_template&.name
      )
    end

    def webhook_campaign_message_payload
      message = webhook_campaign_message
      return nil unless message

      message.payload.merge(
        id: message.id,
        external_message_id: message.external_message_id,
        phone_number: message.phone_number,
        status: message.status,
        failure_reason: message.failure_reason
      )
    end

    def normalized_phone
      digits = (@lead&.display_phone.presence || campaign_recipient&.display_phone).to_s.gsub(/\D/, "")
      return "" if digits.blank?

      digits.length <= 11 ? "55#{digits}" : digits
    end

    def interest_profile_text(profile)
      criteria = profile.with_indifferent_access[:criteria] || {}
      parts = []
      parts << "cidade: #{Array(criteria[:cities]).join(', ')}" if criteria[:cities].present?
      parts << "bairro: #{Array(criteria[:neighborhoods]).join(', ')}" if criteria[:neighborhoods].present?
      parts << "tipo: #{Array(criteria[:categories]).join(', ')}" if criteria[:categories].present?
      parts << "dormitórios: #{criteria[:bedrooms]}" if criteria[:bedrooms].present?
      parts << "confiança: #{profile[:confidence]}%"
      "Perfil de interesse detectado para o lead. #{parts.join(' · ')}"
    end

    def matching_properties_text(matches)
      return "Nenhum imóvel compatível encontrado." if matches.blank?

      matches.map do |result|
        property = result.habitation
        "- ##{property.codigo} #{property.display_title} (#{result.score}%: #{result.reasons.join(', ')})"
      end.join("\n")
    end

    def matching_properties_public_text(matches)
      return nil if matches.blank?

      matches.first(3).map do |result|
        property = result.habitation
        "##{property.codigo} - #{property.display_title}"
      end.join("\n")
    end
  end
end
