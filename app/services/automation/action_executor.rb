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
      when "move_stage"             then "mover para “#{action[:to]}”"
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

    def initialize(lead)
      @lead = lead
    end

    def execute(action)
      action = action.with_indifferent_access

      case action[:type]
      when "create_task"            then act_create_task(action)
      when "send_whatsapp"          then act_send_whatsapp(action, template: false)
      when "send_whatsapp_template" then act_send_whatsapp(action, template: true)
      when "move_stage"             then act_move_stage(action)
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

    def act_create_task(action)
      assignee = task_assignee(action)
      return unless assignee

      task = Task.create!(
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

      conversation = WhatsappConversation.find_or_create_by!(contact_phone: phone) do |record|
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
            body: WhatsappTemplate.find_by(name: action[:template])&.body
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
      Whatsapp::SendMessageJob.perform_later(message.id)
      LeadActivity.log!(lead: @lead, kind: "whatsapp_out", metadata: { body: message.preview, by: "Automação" })
    end

    def act_move_stage(action)
      to = action[:to].to_s
      return if to.blank?
      raise ArgumentError, Automation::StagePolicy.blocked_stage_message(to) unless Automation::StagePolicy.allowed_transition?(to)

      @lead.update(status: to)
      LeadActivity.log!(lead: @lead, kind: "status_change", metadata: { to: @lead.status, by: "Automação" })
    end

    def act_assign_agent(action)
      agent = AdminUser.find_by(id: action[:admin_user_id])
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
      @lead.admin_user || fallback_admin_user(action) || AdminUser.active.first
    end

    def fallback_admin_user(action)
      id = action[:fallback_admin_user_id].presence
      return nil if id.blank?

      AdminUser.active.find_by(id: id)
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
      text.to_s
          .gsub("{{nome}}", @lead.display_name.to_s)
          .gsub("{{corretor}}", @lead.admin_user&.name.to_s)
    end

    def normalized_phone
      digits = @lead.display_phone.to_s.gsub(/\D/, "")
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
