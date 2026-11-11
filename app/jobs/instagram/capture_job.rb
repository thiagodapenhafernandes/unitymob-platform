module Instagram
  class CaptureJob < ApplicationJob
    queue_as :sync

    EMAIL_WAIT = 5.minutes

    def perform(tenant_id, lead_id)
      tenant = Tenant.find_by(id: tenant_id)
      lead = tenant&.leads&.find_by(id: lead_id)
      return unless lead && lead.admin_user_id.nil? && lead.archived_at.blank?
      page = MetaFacebookPage.available_for_distribution(tenant_id).find_by(instagram_id: lead.instagram_account_id, instagram_enabled: true)
      return unless page
      rules = CaptureSettings.new(page, tenant: tenant).rules
      rule = rules.fetch(lead.other_information.dig("instagram_capture", "rule_key") || lead.other_information["meta_campaign_id"].to_s, rules.fetch("default"))
      cursor = lead.other_information.dig("instagram_capture", lead.instagram_capture_pending? ? "cursor" : "sdr_cursor")
      return if cursor && !lead.instagram_messages.inbound.where("id > ?", cursor).exists? && lead.other_information.dig("instagram_capture", "step") != "email" && !(lead.instagram_capture_pending? && CaptureAnswer.complete?(lead))
      return if lead.other_information.fetch("instagram_capture", {}).key?("sdr_cursor") && cursor.nil? && !lead.instagram_capture_pending?
      Reply.with_typing(lead, rule) { process_capture(lead, tenant_id) }
    rescue Instagram::Reply::Error, Faraday::Error, Timeout::Error
      Rails.logger.warn("[Instagram capture] prompt unavailable lead_id=#{lead_id}")
    end

    def process_capture(lead, tenant_id)
      tenant = lead.tenant
      return continue_sdr(lead) unless lead.instagram_capture_pending?

      if lead.other_information.dig("instagram_capture", "step") == "email"
        lead.with_lock do
          state = lead.other_information.fetch("instagram_capture")
          if state["step"] == "email" && CaptureAnswer.complete?(lead) && lead.archived_at.blank? && lead.admin_user_id.nil? &&
              Time.iso8601(state.fetch("email_deadline")) <= Time.current
            finish_capture(lead)
            return
          end
        end
      end

      page = MetaFacebookPage.available_for_distribution(tenant_id)
        .find_by(instagram_id: lead.instagram_account_id, instagram_enabled: true)
      return unless page

      state = lead.other_information.fetch("instagram_capture")
      attribution = resolve_attribution(page, lead) if state["step"] == "start"
      lead.with_lock do
        return unless lead.instagram_capture_pending? && lead.archived_at.blank? && lead.admin_user_id.nil?

        state = lead.other_information.fetch("instagram_capture")
        state = state.merge("step" => lead.client_name.present? ? "phone" : "name") if state["step"] == "email" && !CaptureAnswer.complete?(lead)
        if lead.client_name.present? && lead.client_name.match?(/\A(?:sobre|como|qual|quero|quanto)\b/i) && CaptureAnswer.new(lead.client_name).name.nil?
          lead.client_name = nil
        end
        if state["step"] == "start"
          return unless MetaFacebookPage.available_for_distribution(tenant_id).exists?(id: page.id, instagram_enabled: true)

          rules = CaptureSettings.new(page, tenant: tenant).rules
          start_capture(lead, rules, attribution)
        else
          state = state.merge(CaptureSettings.prompts(current_rule(lead)))
          if CaptureAnswer.complete?(lead) && state["step"] != "email" && !lead.instagram_messages.inbound.where("id > ?", state["cursor"]).exists?
            finish_capture(lead, through: state["cursor"])
          else
            advance_capture(lead, state, page)
          end
        end
      end
    rescue Instagram::Reply::Error, Faraday::Error, Timeout::Error
      Rails.logger.warn("[Instagram capture] prompt unavailable lead_id=#{lead.id}")
    end

    def self.release!(lead, owner: nil)
      return unless lead.instagram_automation_active?

      RoutingContext.apply(lead)
      state = lead.other_information.fetch("instagram_capture")
      if owner
        lead.assign_attributes(admin_user: owner)
        state = state.merge("sdr_cursor" => nil)
      end
      lead.other_information = lead.other_information.merge("instagram_capture" => state.merge("step" => "completed"))
      # Roteamento usa o estado persistido; alterações de captação não são mudanças comerciais.
      lead.update_columns(lead.changes.transform_values(&:last).slice("name", "client_name", "phone", "email", "admin_user_id", "other_information"))
      Leads::RoutingService.route!(lead)
    end

    private

    def resolve_attribution(page, lead)
      entry = lead.other_information.fetch("instagram_entry", {})
      return entry["ad_attribution"] if entry["ad_attribution"].present?

      ad_id = entry.dig("referral", "ad_id")
      integration = page.user_meta_integration
      return if ad_id.blank? || integration.expired? || integration.access_token.blank? || integration.ad_account_ids.empty?

      Facebook::MetaService.new(integration.access_token).ad_attribution(ad_id, account_ids: integration.ad_account_ids)
    rescue Koala::Facebook::APIError, Faraday::Error, Timeout::Error
      Rails.logger.warn("[Instagram capture] campaign unavailable lead_id=#{lead.id}")
      nil
    end

    def start_capture(lead, rules, attribution)
      campaign_id = attribution&.fetch("meta_campaign_id", nil).to_s
      rule = rules.fetch(campaign_id, rules.fetch("default", {}))
      if attribution
        entry = lead.other_information.fetch("instagram_entry")
        lead.other_information = lead.other_information.merge(attribution).merge("instagram_entry" => entry.merge("ad_attribution" => attribution))
      end
      return self.class.release!(lead) unless rule["enabled"]

      initial_messages = lead.instagram_messages.inbound.order(id: :desc).limit(20).to_a.reverse
      cursor = initial_messages.last&.id
      initial_messages.each do |message|
        initial = CaptureAnswer.new(message.body)
        lead.client_name = initial.name if lead.client_name.blank? && initial.name
        lead.phone = initial.phone if initial.phone && !capture_phone(lead.display_phone.to_s)
      end
      step = lead.client_name.present? ? "phone" : "name"
      state = CaptureSettings.prompts(rule).merge("step" => step, "ask_email" => rule["ask_email"] == true, "rule_key" => (rules.key?(campaign_id) ? campaign_id : "default"))
      lead.other_information = lead.other_information.merge("instagram_capture" => state)
      if CaptureAnswer.complete?(lead)
        return ask_for_email(lead, state, cursor) if state["ask_email"] && lead.display_email.blank?
        return finish_capture(lead, through: cursor)
      end
      return if respond_before_contact(lead, state, cursor)
      prompt(lead, state, cursor)
    end

    def advance_capture(lead, state, page)
      messages = lead.instagram_messages.inbound.where("id > ?", state.fetch("cursor")).order(:id).to_a
      message = messages.last
      return unless message

      answer = message.body.to_s.squish
      parsed = CaptureAnswer.new(answer)
      if state["step"] == "email"
        return finish_capture(lead, through: message.id) if answer.casecmp?("pular")
        if answer.length <= 254 && URI::MailTo::EMAIL_REGEXP.match?(answer)
          lead.email = answer if lead.display_email.blank?
          return finish_capture(lead, through: message.id)
        end
        state = state.merge("pending_question_id" => message.id) if parsed.request?
        lead.other_information = lead.other_information.deep_merge("instagram_capture" => state)
        return finish_capture(lead, through: message.id)
      else
        messages.each do |entry|
          data = CaptureAnswer.new(entry.body)
          lead.client_name = data.name if lead.client_name.blank? && data.name
          lead.phone = data.phone if data.phone && !capture_phone(lead.display_phone.to_s)
          if data.request?
            state = state.merge("pending_question_id" => entry.id)
          end
        end
        lead.other_information = lead.other_information.deep_merge("instagram_capture" => state)
        if CaptureAnswer.complete?(lead)
          return ask_for_email(lead, state, message.id) if state["ask_email"] && lead.display_email.blank?
          return finish_capture(lead, through: message.id)
        end
        return if respond_before_contact(lead, state, message.id)
        if lead.client_name.present? && state["step"] == "name"
          return prompt(lead, state.merge("step" => "phone"), message.id)
        end
      end
      remind_missing_contact(lead, state, message)
    end

    def remind_missing_contact(lead, state, message)
      missing_name = CaptureAnswer.new(lead.client_name).name.blank?
      missing_phone = capture_phone(lead.display_phone.to_s).blank?
      step = missing_name ? "name" : "phone"
      count = state["contact_reminders"].to_i
      rule = current_rule(lead)
      key = count.positive? ? "waiting_contact" : (missing_name && missing_phone ? "missing_both" : (missing_name ? "missing_name" : "missing_phone"))
      body = CaptureSettings.message(rule, key, lead)
      # Uma mensagem nova pode receber orientação; jobs repetidos não reenviam o pedido.
      send_catalog_reply(lead, body) unless lead.instagram_messages.outbound.order(:id).last&.body == body
      lead.other_information = lead.other_information.deep_merge("instagram_capture" => state.merge(
        "step" => step, "cursor" => message.id, "contact_reminders" => count + 1
      ))
      lead.update_columns(lead.changes.transform_values(&:last).slice("client_name", "phone", "other_information"))
    end

    def ask_for_email(lead, state, cursor)
      deadline = EMAIL_WAIT.from_now
      prompt(lead, state.merge("step" => "email", "email_deadline" => deadline.iso8601(6)), cursor)
      self.class.set(wait_until: deadline).perform_later(lead.tenant_id, lead.id)
    rescue Instagram::Reply::Error, Faraday::Error, Timeout::Error
      finish_capture(lead)
    end

    def finish_capture(lead, thank_you: true, through: nil)
      return unless CaptureAnswer.complete?(lead)
      RoutingContext.apply(lead)
      state = lead.other_information.fetch("instagram_capture")
      cursor = through || lead.instagram_messages.inbound.maximum(:id)
      if lead.client_name.present? && (lead.name.blank? || lead.name == ProfileEnrichmentJob::DEFAULT_NAME || lead.name.start_with?("@"))
        lead.name = lead.client_name
      end
      lead.other_information = lead.other_information.deep_merge("instagram_capture" => {
        "step" => "serving", "sdr_cursor" => cursor, "sdr_started_after" => cursor
      })
      lead.update_columns(lead.changes.transform_values(&:last).slice("name", "client_name", "phone", "email", "other_information"))
      page = MetaFacebookPage.available_for_distribution(lead.tenant_id).find_by(instagram_id: lead.instagram_account_id, instagram_enabled: true)
      rules = page ? CaptureSettings.new(page, tenant: lead.tenant).rules : {}
      rule = rules.fetch(state["rule_key"], rules.fetch("default", {}))
      question = lead.instagram_messages.inbound.find_by(id: state["pending_question_id"]) if state["pending_question_id"]
      question ||= lead.instagram_messages.inbound.order(id: :desc).limit(20).detect do |message|
        data = CaptureAnswer.new(message.body)
        data.request?
      end
      if rule["sdr_enabled"] && (question || Leads::EntryClassification.new(lead).nature == :commercial)
        response = contextual_response(lead, rule, conversation_history(lead, question&.id || cursor), first_turn: true)
        send_catalog_reply(lead, response, handoff_cursor: cursor)
        return
      end
      handoff_to_team(lead, cursor) unless rule["sdr_enabled"]
      return unless thank_you && state["thank_you_prompt"].present?

      name = lead.client_name.to_s.split.first.presence || "por enviar seus dados"
      body = state.fetch("thank_you_prompt").gsub("{primeiro_nome}") { name }.first(Reply::MAX_CHARS)
      Reply.call(lead: lead, body: body, admin_user: nil, typing: false)
    rescue Reply::Error, Faraday::Error, Timeout::Error
      Rails.logger.warn("[Instagram capture] completion reply unavailable lead_id=#{lead.id}")
    end

    def continue_sdr(lead)
      lead.with_lock do
        return if lead.admin_user_id.present? || lead.archived_at.present? || !Reply.window_open?(lead)
        return if lead.instagram_messages.where.not(sent_by_admin_user_id: nil).exists?

        state = lead.other_information.fetch("instagram_capture", {})
        return if state.key?("sdr_cursor") && state["sdr_cursor"].nil?

        page = MetaFacebookPage.available_for_distribution(lead.tenant_id)
          .find_by(instagram_id: lead.instagram_account_id, instagram_enabled: true)
        return unless page

        rules = CaptureSettings.new(page, tenant: lead.tenant).rules
        rule_key = state["rule_key"] || lead.other_information["meta_campaign_id"].to_s
        rule = rules.fetch(rule_key, rules.fetch("default", {}))
        return unless rule["enabled"] && rule["sdr_enabled"]
        return if InternalSender.match?(tenant: lead.tenant, page: page, sender_id: lead.instagram_scoped_id)

        messages = lead.instagram_messages.inbound.where("id > ?", state["sdr_cursor"] || 0).order(id: :desc)
        newest = messages.first
        return if newest&.body.blank?

        unless CaptureAnswer.complete?(lead)
          state = state.merge("step" => lead.client_name.present? ? "phone" : "name", "cursor" => newest.id - 1)
          return advance_capture(lead, state, page)
        end
        parsed = CaptureAnswer.new(newest.body)
        lead.client_name = parsed.name(explicit_only: true) if lead.client_name.blank? && parsed.name(explicit_only: true)
        lead.phone = parsed.phone if parsed.phone && !capture_phone(lead.display_phone.to_s)
        if lead.client_name.present? && (lead.name.blank? || lead.name == ProfileEnrichmentJob::DEFAULT_NAME || lead.name.start_with?("@"))
          lead.name = lead.client_name
        end
        lead.update_columns(lead.changes.transform_values(&:last).slice("name", "client_name", "phone")) if lead.changed?
        RoutingContext.apply(lead)
        lead.update_columns(other_information: lead.other_information) if lead.will_save_change_to_other_information?
        history = conversation_history(lead, newest.id)
        first_turn = state["sdr_cursor"] == state["sdr_started_after"]
        answer = contextual_response(lead, rule, history, first_turn: first_turn)
        send_catalog_reply(lead, answer, handoff_cursor: newest.id)
        updates = { "sdr_cursor" => newest.id }
        if answer == CatalogReply::HANDOFF
          updates["sdr_cursor"] = lead.admin_user_id.present? ? nil : newest.id
        end
        lead.update_columns(other_information: lead.other_information.deep_merge("instagram_capture" => updates))
      end
    end

    def handoff_to_team(lead, cursor)
      return unless CaptureAnswer.complete?(lead)
      RoutingContext.apply(lead)
      lead.update_columns(other_information: lead.other_information.deep_merge("instagram_capture" => {"step" => "completed", "sdr_cursor" => nil}))
      key = lead.activities.where(kind: "note").where("metadata ->> 'instagram_handoff_cursor' = ?", cursor.to_s)
      unless key.exists?
        lead.activities.create!(kind: "note", source_category: "automation", metadata: {
          "body" => "A automação encaminhou o contato para atendimento da equipe.", "instagram_handoff_cursor" => cursor
        })
        Leads::RoutingService.route!(lead) if lead.admin_user_id.blank?
        if lead.admin_user
          Leads::NotificationDispatcher.push_to(lead.admin_user, title: "Cliente aguarda resposta no Instagram",
            body: "O cliente aguarda atendimento da equipe no Instagram.", url: "/admin/leads/#{lead.id}#lead-instagram-thread", lead: lead, event: "instagram_handoff")
        end
      end
      if lead.admin_user_id.nil?
        lead.update_columns(other_information: lead.other_information.deep_merge("instagram_capture" => {
          "step" => "handoff_pending", "sdr_cursor" => cursor
        }))
      end
    end

    def conversation_history(lead, through)
      lead.instagram_messages.where("id <= ?", through).where.not(body: "").order(id: :desc).limit(10)
        .pluck(:direction, :body).reverse.map do |direction, body|
          text = body.to_s.squish.first(direction == "inbound" ? 300 : Reply::MAX_CHARS)
            .gsub(/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/, "[e-mail]")
            .gsub(/\+?\d[\d ().-]{8,}\d/, "[telefone]")
          { role: direction == "inbound" ? "cliente" : "assistente", text: text }
        end
    end

    def respond_before_contact(lead, state, cursor)
      return false unless cursor
      rule = current_rule(lead)
      history = conversation_history(lead, cursor)
      condition = ConversationCondition.match(lead, rule, history)
      return false unless condition && condition['require_contact'] == false && condition['action'] != 'handoff'
      response = contextual_response(lead, rule.merge('allow_incomplete_contact' => true), history, first_turn: state['cursor'].nil?, condition: condition)
      return false if response.blank? || response == CatalogReply::HANDOFF
      send_catalog_reply(lead, response)
      lead.other_information = lead.other_information.deep_merge("instagram_capture" => state.merge("cursor" => cursor))
      lead.update_columns(lead.changes.transform_values(&:last).slice("client_name", "phone", "other_information"))
      true
    end

    def current_rule(lead)
      page = MetaFacebookPage.available_for_distribution(lead.tenant_id).find_by(instagram_id: lead.instagram_account_id, instagram_enabled: true)
      return CaptureSettings.defaults unless page
      rules = CaptureSettings.new(page, tenant: lead.tenant).rules
      rules.fetch(lead.other_information.dig("instagram_capture", "rule_key"), rules.fetch("default"))
    end

    def contextual_response(lead, rule, history, first_turn:, condition: nil)
      condition ||= ConversationCondition.match(lead, rule, history)
      return unless condition
      if CaptureAnswer.complete?(lead) && condition['match'] == 'always' && condition['action'] == 'ai' && condition['ai_enabled'] == true &&
          Leads::EntryClassification.new(lead).nature == :commercial
        return CatalogReply::HANDOFF
      end
      case condition['action']
      when 'fixed' then condition['response'].to_s
      when 'handoff' then CatalogReply::HANDOFF
      when 'ai'
        CatalogReply.new(lead, rule).call(history, first_turn: first_turn) if condition['ai_enabled'] == true
      else CatalogReply::HANDOFF
      end
    end

    def send_catalog_reply(lead, answer, handoff_cursor: nil)
      handoff = answer == CatalogReply::HANDOFF
      return if lead.admin_user_id.present? || answer.blank?
      answer = CaptureSettings.message(current_rule(lead), "handoff", lead) if handoff
      if answer.is_a?(CatalogReply::Recommendation)
        Reply.call(lead: lead, body: answer.body, admin_user: nil, typing: false, cards: answer.cards)
      else
        Reply.call(lead: lead, body: answer.first(Reply::MAX_CHARS), admin_user: nil, typing: false)
      end
    ensure
      handoff_to_team(lead, handoff_cursor) if handoff && handoff_cursor
    end

    def capture_phone(answer)
      CaptureAnswer.new(answer).phone
    end

    def prompt(lead, state, cursor)
      # shortcut: a API não confirma o resultado de um timeout, conciliar com o histórico antes de habilitar retry automático de envio.
      message = Reply.call(lead: lead, body: state.fetch("#{state.fetch('step')}_prompt"), admin_user: nil, typing: false)
      lead.other_information = lead.other_information.merge("instagram_capture" => state.merge(
        "cursor" => cursor, "prompted_at" => message.occurred_at.iso8601(6)
      ))
      lead.update_columns(lead.changes.transform_values(&:last).slice("client_name", "phone", "other_information"))
    end
  end
end
