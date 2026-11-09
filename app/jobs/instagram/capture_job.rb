module Instagram
  class CaptureJob < ApplicationJob
    queue_as :sync

    EMAIL_WAIT = 5.minutes

    def perform(tenant_id, lead_id)
      tenant = Tenant.find_by(id: tenant_id)
      lead = tenant&.leads&.find_by(id: lead_id)
      return unless lead
      return continue_sdr(lead) unless lead.instagram_capture_pending?

      if lead.other_information.dig("instagram_capture", "step") == "email"
        lead.with_lock do
          state = lead.other_information.fetch("instagram_capture")
          if state["step"] == "email" && lead.archived_at.blank? && lead.admin_user_id.nil? &&
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
        if lead.client_name.present? && lead.client_name.match?(/\A(?:sobre|como|qual|quero|quanto)\b/i) && CaptureAnswer.new(lead.client_name).name.nil?
          lead.client_name = nil
        end
        if state["step"] == "start"
          return unless MetaFacebookPage.available_for_distribution(tenant_id).exists?(id: page.id, instagram_enabled: true)

          rules = CaptureSettings.new(page, tenant: tenant).rules
          start_capture(lead, rules, attribution)
        else
          advance_capture(lead, state.merge(CaptureSettings.prompts(state)), page)
        end
      end
    rescue Instagram::Reply::Error, Faraday::Error, Timeout::Error
      Rails.logger.warn("[Instagram capture] prompt unavailable lead_id=#{lead_id}")
    end

    def self.release!(lead, owner: nil)
      return unless lead.instagram_capture_pending?

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
      if capture_phone(lead.display_phone.to_s)
        return ask_for_email(lead, state, cursor) if state["ask_email"] && lead.display_email.blank?
        return finish_capture(lead, through: cursor)
      end
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
      else
        if parsed.declined?
          Reply.call(lead: lead, body: "Claro, podemos continuar pelo Instagram.", admin_user: nil, typing: true)
          return finish_capture(lead, thank_you: false, through: message.id)
        end
        messages.each do |entry|
          data = CaptureAnswer.new(entry.body)
          lead.client_name = data.name if lead.client_name.blank? && data.name
          lead.phone = data.phone if data.phone && !capture_phone(lead.display_phone.to_s)
        end
        if capture_phone(lead.display_phone.to_s)
          return ask_for_email(lead, state, message.id) if state["ask_email"] && lead.display_email.blank?
          return finish_capture(lead, through: message.id)
        end
        if lead.client_name.present? && state["step"] == "name"
          return prompt(lead, state.merge("step" => "phone"), message.id)
        end
      end

      # Consome a resposta mesmo sem dados pessoais; nunca reenvia a pergunta do cadastro.
      rules = CaptureSettings.new(page, tenant: lead.tenant).rules
      rule = rules.fetch(state["rule_key"], rules.fetch("default", {}))
      history = conversation_history(lead, message.id)
      response = if answer.match?(/\A[\d() .+-]+\z/) && state["phone_guidance"] != true
        state = state.merge("phone_guidance" => true)
        "Para usar o WhatsApp, o número precisa incluir o DDD. Se preferir, podemos continuar pelo Instagram."
      elsif rule["sdr_enabled"]
        CatalogReply.new(lead, rule).call(history, first_turn: state["contextual_turns"].to_i.zero?)
      else
        CatalogReply::HANDOFF
      end
      response = CatalogReply::HANDOFF if response.is_a?(String) && lead.instagram_messages.outbound.order(:id).last&.body == response
      send_catalog_reply(lead, response)
      state = state.merge("cursor" => message.id, "contextual_turns" => state["contextual_turns"].to_i + 1)
      lead.other_information = lead.other_information.deep_merge("instagram_capture" => state)
      lead.update_columns(lead.changes.transform_values(&:last).slice("client_name", "phone", "other_information"))
      if response == CatalogReply::HANDOFF
        finish_capture(lead, thank_you: false, through: message.id)
        lead.update_columns(other_information: lead.other_information.deep_merge("instagram_capture" => { "sdr_cursor" => nil }))
      end
    end

    def ask_for_email(lead, state, cursor)
      deadline = EMAIL_WAIT.from_now
      prompt(lead, state.merge("step" => "email", "email_deadline" => deadline.iso8601(6)), cursor)
      self.class.set(wait_until: deadline).perform_later(lead.tenant_id, lead.id)
    rescue Instagram::Reply::Error, Faraday::Error, Timeout::Error
      finish_capture(lead)
    end

    def finish_capture(lead, thank_you: true, through: nil)
      state = lead.other_information.fetch("instagram_capture")
      cursor = through || lead.instagram_messages.inbound.maximum(:id)
      if lead.client_name.present? && (lead.name.blank? || lead.name == ProfileEnrichmentJob::DEFAULT_NAME || lead.name.start_with?("@"))
        lead.name = lead.client_name
      end
      self.class.release!(lead)
      lead.update_columns(other_information: lead.other_information.deep_merge(
        "instagram_capture" => { "sdr_cursor" => cursor, "sdr_started_after" => cursor }
      ))
      return unless thank_you && state["thank_you_prompt"].present?

      name = lead.client_name.to_s.split.first.presence || "por enviar seus dados"
      body = state.fetch("thank_you_prompt").gsub("{primeiro_nome}") { name }.first(Reply::MAX_CHARS)
      Reply.call(lead: lead, body: body, admin_user: nil, typing: true)
    rescue Reply::Error, Faraday::Error, Timeout::Error
      Rails.logger.warn("[Instagram capture] completion reply unavailable lead_id=#{lead.id}")
    end

    def continue_sdr(lead)
      lead.with_lock do
        return if lead.archived_at.present? || !Reply.window_open?(lead)
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

        parsed = CaptureAnswer.new(newest.body)
        lead.client_name = parsed.name(explicit_only: true) if lead.client_name.blank? && parsed.name(explicit_only: true)
        lead.phone = parsed.phone if parsed.phone && !capture_phone(lead.display_phone.to_s)
        if lead.client_name.present? && (lead.name.blank? || lead.name == ProfileEnrichmentJob::DEFAULT_NAME || lead.name.start_with?("@"))
          lead.name = lead.client_name
        end
        lead.update_columns(lead.changes.transform_values(&:last).slice("name", "client_name", "phone")) if lead.changed?
        history = conversation_history(lead, newest.id)
        first_turn = state["sdr_cursor"] == state["sdr_started_after"]
        answer = CatalogReply.new(lead, rule).call(history, first_turn: first_turn)
        send_catalog_reply(lead, answer)
        updates = { "sdr_cursor" => newest.id }
        updates["sdr_cursor"] = nil if answer == CatalogReply::HANDOFF
        lead.update_columns(other_information: lead.other_information.deep_merge("instagram_capture" => updates))
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

    def send_catalog_reply(lead, answer)
      if answer.is_a?(CatalogReply::Recommendation)
        Reply.call(lead: lead, body: answer.body, admin_user: nil, typing: true, cards: answer.cards)
      else
        Reply.call(lead: lead, body: answer.first(Reply::MAX_CHARS), admin_user: nil, typing: true)
      end
    end

    def capture_phone(answer)
      CaptureAnswer.new(answer).phone
    end

    def prompt(lead, state, cursor)
      # shortcut: a API não confirma o resultado de um timeout, conciliar com o histórico antes de habilitar retry automático de envio.
      message = Reply.call(lead: lead, body: state.fetch("#{state.fetch('step')}_prompt"), admin_user: nil, typing: true)
      lead.other_information = lead.other_information.merge("instagram_capture" => state.merge(
        "cursor" => cursor, "prompted_at" => message.occurred_at.iso8601(6)
      ))
      lead.update_columns(lead.changes.transform_values(&:last).slice("client_name", "phone", "other_information"))
    end
  end
end
