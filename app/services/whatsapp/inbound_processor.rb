module Whatsapp
  # Processa o payload do webhook da WhatsApp Cloud API:
  # - mensagens recebidas -> cria/atualiza conversa + mensagem + vincula lead + timeline
  # - status (sent/delivered/read) -> atualiza a mensagem enviada
  class InboundProcessor
    MESSAGE_STATUS_PROGRESS = {
      "pending" => 0,
      "sent" => 1,
      "delivered" => 2,
      "read" => 3
    }.freeze

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = payload.is_a?(Hash) ? payload : {}
    end

    def call
      Array(@payload["entry"]).each do |entry|
        Array(entry["changes"]).each do |change|
          value = change["value"] || {}
          @tenant_resolution_ambiguous = false
          @tenant = tenant_from_payload(value)
          Current.tenant = @tenant

          begin
            if @tenant_resolution_ambiguous
              Rails.logger.warn("[wa webhook] tenant ambiguo; change ignorado para evitar vazamento entre contas")
              next
            end
            if @tenant.blank?
              Rails.logger.warn("[wa webhook] tenant nao identificado; change ignorado para evitar fallback inseguro")
              next
            end

            capture_bsuid_payload(change) # Fase 0: visibilidade dos webhooks reais

            # Webhook dedicado de mudança de BSUID (field "user_id_update").
            if change["field"].to_s == "user_id_update" || value["user_id_update"].present?
              handle_user_id_update(value)
              next
            end

            if change["field"].to_s == "message_template_status_update"
              handle_template_status_update(value)
              next
            end

            contacts = index_contacts(value["contacts"])
            Array(value["messages"]).each { |msg| handle_inbound(msg, contacts) }
            Array(value["statuses"]).each { |st| handle_status(st) }
          ensure
            Current.tenant = nil
            @tenant = nil
          end
        end
      end
      true
    end

    private

    # Indexa contatos por telefone (wa_id) E por BSUID (user_id), guardando o nome,
    # para enriquecer a conversa independentemente da identidade do remetente.
    def index_contacts(contacts)
      Array(contacts).each_with_object({}) do |c, acc|
        info = {
          name:  c.dig("profile", "name").presence || c.dig("profile", "username").presence,
          wa_id: c["wa_id"].presence,
          bsuid: c["user_id"].presence
        }
        acc[c["wa_id"].to_s]   = info if c["wa_id"].present?
        acc[c["user_id"].to_s] = info if c["user_id"].present?
      end
    end

    def handle_inbound(msg, contacts)
      return if tenant.whatsapp_messages.exists?(wa_message_id: msg["id"]) # dedup pelo id da mensagem no tenant
      return if msg["type"].to_s == "system" # eventos de sistema (ex.: troca de número) não são mensagens

      # Campos oficiais da Meta: `from` (telefone, pode faltar quando o número está
      # escondido) e `from_user_id` (BSUID). Aceita qualquer um dos dois.
      phone = msg["from"].presence
      bsuid = msg["from_user_id"].presence
      return if phone.blank? && bsuid.blank? # nenhuma identidade utilizável

      contact = contacts[phone.to_s] || contacts[bsuid.to_s] || {}
      name = contact[:name]

      conversation = find_or_create_conversation(phone: phone, bsuid: bsuid, name: name)
      type = msg["type"].to_s

      # Reação do cliente: marca a mensagem alvo (não cria bolha nova)
      if type == "reaction"
        handle_reaction(conversation, msg)
        return
      end

      body = extract_body(msg, type)
      media_url = extract_media_url(msg, type)

      message = begin
        conversation.messages.create!(
          direction: "inbound",
          wa_message_id: msg["id"],
          msg_type: type.presence || "text",
          body: body,
          media_url: media_url,
          **(WhatsappMessage.column_names.include?("context_wa_message_id") ? { context_wa_message_id: msg.dig("context", "id") } : {}),
          status: "delivered",
          delivered_at: Time.current
        )
      rescue ActiveRecord::RecordNotUnique
        # Corrida entre entregas simultâneas da Meta: o índice único
        # (tenant_id, wa_message_id) garantiu a 1ª gravação — duplicata silenciosa.
        Rails.logger.info("[wa inbound] mensagem duplicada ignorada wa_message_id=#{msg["id"].inspect}")
        return
      end

      attach_remote_media(message, msg, type, media_url) if media_url.present?

      # Incremento atômico no banco (evita lost update entre workers concorrentes);
      # reload sincroniza o objeto antes do broadcast serializar unread_count.
      WhatsappConversation.update_counters(conversation.id, unread_count: 1, touch: true)
      conversation.reload
      conversation.touch_last_message!(message)
      Whatsapp::ThreadBroadcaster.message_created(message)

      campaign_message = mark_campaign_reply!(conversation, message, raw_message: msg)

      if conversation.lead_id
        meta = { body: message.preview, phone: phone, bsuid: bsuid }.compact
        LeadActivity.log!(lead: conversation.lead, kind: "whatsapp_in", metadata: meta)
        Automation::Dispatcher.dispatch(
          :whatsapp_received,
          conversation.lead,
          source: "whatsapp",
          payload: { whatsapp_message_id: message.id, wa_message_id: message.wa_message_id, phone: phone, bsuid: bsuid }.compact,
          idempotency_key: "whatsapp_received:#{message.id}"
        )
      end
    end

    # BSUID mudou (webhook user_id_update): re-vincula conversa/lead do BSUID antigo
    # para o novo. Estrutura oficial: array com { user_id: { previous, current } }.
    def handle_user_id_update(value)
      Array(value["user_id_update"]).each do |entry|
        old_id = entry.dig("user_id", "previous").presence
        new_id = entry.dig("user_id", "current").presence
        next if old_id.blank? || new_id.blank?

        tenant.whatsapp_conversations.where(business_scoped_user_id: old_id)
              .update_all(business_scoped_user_id: new_id, updated_at: Time.current)
        tenant.leads.where(business_scoped_user_id: old_id)
              .update_all(business_scoped_user_id: new_id, updated_at: Time.current)
        Rails.logger.info("[wa-bsuid] user_id_update #{old_id} -> #{new_id}")
      end
    end

    # Fase 0: registra a presença de BSUID nos webhooks reais (sem corpo de mensagem).
    def capture_bsuid_payload(change)
      value = change["value"]
      contacts = Array(value && value["contacts"])
      has_bsuid = contacts.any? { |c| c["user_id"].present? }
      return unless has_bsuid || change["field"].to_s == "user_id_update" || (value && value["user_id_update"].present?)

      summary = {
        field: change["field"],
        contacts: contacts.map { |c| { wa_id: c["wa_id"], user_id: c["user_id"] } },
        user_id_update: value && value["user_id_update"]
      }.compact
      Rails.logger.info("[wa-bsuid] #{summary.to_json}")
    rescue => e
      Rails.logger.warn("[wa-bsuid] capture falhou: #{e.message}")
    end

    def handle_template_status_update(value)
      template_id = value["message_template_id"].presence&.to_s
      template_name = value["message_template_name"].presence
      language = value["message_template_language"].presence || "pt_BR"
      event = value["event"].presence&.to_s&.upcase
      reason = value["reason"].presence

      template = if template_id.present?
                   tenant.whatsapp_templates.find_by(meta_id: template_id)
                 end
      template ||= tenant.whatsapp_templates.find_by(name: template_name, language: language) if template_name.present?

      unless template
        Rails.logger.warn(
          "[wa-template-status] template nao encontrado " \
          "meta_id=#{template_id.inspect} name=#{template_name.inspect} language=#{language.inspect} event=#{event.inspect}"
        )
        return
      end

      attrs = { updated_at: Time.current }
      attrs[:status] = event if event.present? && event != "NONE"
      attrs[:submission_error] = template_submission_error(event, reason)
      template.update_columns(attrs)

      Rails.logger.info(
        "[wa-template-status] template=#{template.name.inspect} meta_id=#{template.meta_id.inspect} " \
        "status=#{template.status.inspect} reason=#{reason.inspect}"
      )
    end

    def template_submission_error(event, reason)
      return nil if event.to_s == "APPROVED"
      return reason if reason.present?
      return nil if event.blank? || event == "NONE" || event == "PENDING"

      "Status retornado pela Meta: #{event}"
    end

    def handle_status(status)
      message = tenant.whatsapp_messages.find_by(wa_message_id: status["id"])
      return unless message

      backfill_conversation_phone(message.whatsapp_conversation, status["recipient_id"])

      state = status["status"].to_s
      return unless WhatsappMessage::STATUSES.include?(state)

      attrs = message_status_attrs(message, state, status)
      return if attrs.blank?

      attrs[:recipient_user_id] = status["recipient_user_id"] if status["recipient_user_id"].present?
      attrs[:error_message] = status.dig("errors", 0, "title") if state == "failed"
      message.update_columns(attrs.merge(updated_at: Time.current))
      Whatsapp::ThreadBroadcaster.message_updated(message)

      campaign_message = tenant.whatsapp_campaign_messages.find_by(external_message_id: status["id"])
      return unless campaign_message

      occurred_at = status["timestamp"].present? ? Time.zone.at(status["timestamp"].to_i) : Time.current
      case state
      when "sent"
        campaign_message.mark_accepted_by_meta!(
          message_id: status["id"],
          whatsapp_message: message,
          at: occurred_at
        )
      when "delivered"
        campaign_message.mark_delivered!(at: occurred_at)
      when "read"
        campaign_message.mark_read!(at: occurred_at)
      when "failed"
        campaign_message.mark_failed!(attrs[:error_message].presence || "Falha informada pela Meta")
      end
    end

    def message_status_attrs(message, state, status)
      current = message.status.to_s
      timestamp = status_timestamp(status)

      if state == "failed"
        return if MESSAGE_STATUS_PROGRESS.fetch(current, -1) >= MESSAGE_STATUS_PROGRESS.fetch("delivered")

        return { status: state }
      end

      next_rank = MESSAGE_STATUS_PROGRESS[state]
      current_rank = MESSAGE_STATUS_PROGRESS.fetch(current, -1)
      return if next_rank.blank? || next_rank < current_rank

      attrs = { status: state }
      attrs[:delivered_at] = timestamp if state == "delivered" && timestamp.present?
      attrs[:read_at] = timestamp if state == "read" && timestamp.present?
      attrs
    end

    def status_timestamp(status)
      return if status["timestamp"].blank?

      Time.zone.at(status["timestamp"].to_i)
    end

    def mark_campaign_reply!(conversation, inbound_message, raw_message:)
      campaign_message = nil
      if conversation.lead_id.present?
        campaign_message = WhatsappCampaignMessage
          .joins(:whatsapp_campaign)
          .where(lead_id: conversation.lead_id)
          .where(tenant: tenant)
          .where(status: %w[sent delivered read])
          .where(whatsapp_campaigns: { status: %w[processing completed] })
          .order(sent_at: :desc, id: :desc)
          .first
      end
      campaign_message ||= campaign_reply_candidate(conversation.contact_phone)

      return unless campaign_message

      campaign_message.mark_replied!(
        at: inbound_message.created_at,
        inbound_message: inbound_message,
        raw_payload: raw_message
      )
      link_conversation_to_campaign_lead!(conversation, campaign_message)
      campaign_message
    end

    def link_conversation_to_campaign_lead!(conversation, campaign_message)
      campaign_message.reload
      lead = campaign_message.lead
      return unless lead
      return if conversation.lead_id == lead.id

      conversation.update_column(:lead_id, lead.id)
    end

    def campaign_reply_candidate(phone)
      normalized = Phones::Normalizer.call(phone).to_s
      return if normalized.blank?

      WhatsappCampaignMessage
        .left_joins(:whatsapp_campaign_recipient)
        .joins(:whatsapp_campaign)
        .where(tenant: tenant)
        .where(status: %w[sent delivered read])
        .where(whatsapp_campaigns: { status: %w[processing completed] })
        .where(
          "whatsapp_campaign_messages.phone_number = :phone OR whatsapp_campaign_recipients.phone_number = :phone",
          phone: normalized
        )
        .order(sent_at: :desc, id: :desc)
        .first
    end

    def handle_reaction(conversation, msg)
      return unless WhatsappMessage.column_names.include?("client_reaction")

      target = conversation.messages.find_by(wa_message_id: msg.dig("reaction", "message_id"))
      return if target.blank?

      target.update_columns(client_reaction: msg.dig("reaction", "emoji").presence, updated_at: Time.current)
      Whatsapp::ThreadBroadcaster.message_updated(target)
    end

    def extract_body(msg, type)
      case type
      when "text" then msg.dig("text", "body")
      when "button" then msg.dig("button", "text")
      when "interactive" then msg.dig("interactive", "button_reply", "title") || msg.dig("interactive", "list_reply", "title")
      when "image", "document", "audio", "video" then msg.dig(type, "caption")
      else nil
      end.to_s
    end

    def extract_media_url(msg, type)
      return unless %w[image document audio video].include?(type.to_s)

      media_id = msg.dig(type, "id").presence
      return if media_id.blank?

      client = Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(tenant))
      result = client.media_url(media_id)
      return result[:url] if result[:ok]

      Rails.logger.warn("[wa inbound] media fetch failed for #{type} #{media_id}: #{result[:error]}")
      nil
    rescue => e
      Rails.logger.warn("[wa inbound] media fetch exception for #{type}: #{e.message}")
      nil
    end

    def attach_remote_media(message, msg, type, media_url)
      return if message.media_file.attached?

      client = Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(tenant))
      download = client.download_media(media_url)
      return Rails.logger.warn("[wa inbound] media download failed for #{message.wa_message_id}: #{download[:error]}") unless download[:ok]

      metadata = extract_media_metadata(msg, type)
      filename = metadata[:filename].presence || inferred_media_filename(message, type, download[:content_type])
      content_type = download[:content_type].presence || metadata[:content_type].presence || "application/octet-stream"

      message.media_file.attach(
        io: StringIO.new(download[:body]),
        filename: filename,
        content_type: content_type
      )
    rescue => e
      Rails.logger.warn("[wa inbound] media attach failed for #{message.wa_message_id}: #{e.message}")
    end

    def extract_media_metadata(msg, type)
      payload = msg[type].is_a?(Hash) ? msg[type] : {}
      {
        filename: payload["filename"].presence,
        content_type: payload["mime_type"].presence
      }
    end

    def inferred_media_filename(message, type, content_type)
      extension = Rack::Mime::MIME_TYPES.invert[content_type.to_s]&.delete_prefix(".")
      base = [type.presence || "media", message.wa_message_id.presence || message.id].compact.join("-")
      extension.present? ? "#{base}.#{extension}" : base
    end

    # Conversas CTWA nascem so com BSUID (telefone oculto no `from`), mas os
    # STATUSES revelam o numero em recipient_id. Com contact_phone preenchido,
    # os envios passam a usar o fluxo por telefone — onde a Meta respeita
    # context (Responder) e reacoes, ignorados silenciosamente no fluxo BSUID.
    def backfill_conversation_phone(conversation, recipient_phone)
      return if conversation.blank? || recipient_phone.blank?
      return if conversation.contact_phone.present?
      return if tenant.whatsapp_conversations.where(contact_phone: recipient_phone).where.not(id: conversation.id).exists?

      conversation.update_columns(contact_phone: recipient_phone, updated_at: Time.current)
    end

    def find_or_create_conversation(phone:, bsuid:, name:)
      conversation =
        (phone.present? && tenant.whatsapp_conversations.find_by(contact_phone: phone)) ||
        (bsuid.present? && tenant.whatsapp_conversations.find_by(business_scoped_user_id: bsuid)) ||
        tenant.whatsapp_conversations.new

      # Backfill: completa a identidade que faltava (mescla telefone + BSUID).
      conversation.contact_phone = phone if phone.present? && conversation.contact_phone.blank?
      conversation.business_scoped_user_id = bsuid if bsuid.present? && conversation.business_scoped_user_id.blank?
      conversation.contact_name = name if name.present? && conversation.contact_name.blank?
      conversation.status = "open"

      if conversation.lead_id.blank? && campaign_reply_candidate(phone).blank?
        conversation.lead = link_or_create_lead(phone: phone, bsuid: bsuid, name: name)
      end

      conversation.save!
      conversation
    end

    def link_or_create_lead(phone:, bsuid:, name:)
      # 1) Por BSUID (identidade estável).
      if bsuid.present?
        lead = tenant.leads.find_by(business_scoped_user_id: bsuid)
        return lead if lead
      end

      # 2) Por telefone (últimos 8 dígitos), e backfill do BSUID quando o conhecemos.
      if phone.present?
        tail = phone.gsub(/\D/, "").last(8)
        lead = tenant.leads.where("regexp_replace(coalesce(phone, ''), '\\D', '', 'g') LIKE ?", "%#{tail}").first
        if lead
          lead.update_column(:business_scoped_user_id, bsuid) if bsuid.present? && lead.business_scoped_user_id.blank?
          return lead
        end
      end

      tenant.leads.create!(
        name: name.presence || "Contato WhatsApp #{phone || bsuid}",
        phone: phone,
        business_scoped_user_id: bsuid,
        origin: "whatsapp",
        status: Lead.default_status
      )
    rescue => e
      Rails.logger.warn("[wa inbound] lead link failed: #{e.message}")
      nil
    end

    def tenant
      @tenant || Current.tenant || raise(ArgumentError, "Tenant obrigatório para webhook WhatsApp")
    end

    def tenant_from_payload(value)
      phone_number_id = value.dig("metadata", "phone_number_id").presence || value["phone_number_id"].presence
      if phone_number_id.present?
        sender_tenant = unique_tenant_from_relation(WhatsappSenderNumber.where(phone_number_id: phone_number_id))
        return sender_tenant if sender_tenant

        integration_tenant = unique_tenant_from_relation(WhatsappBusinessIntegration.where(phone_number_id: phone_number_id))
        return integration_tenant if integration_tenant
      end

      waba_id = value["whatsapp_business_account_id"].presence || value["waba_id"].presence
      if waba_id.present?
        integration_tenant = unique_tenant_from_relation(WhatsappBusinessIntegration.where(waba_id: waba_id))
        return integration_tenant if integration_tenant
      end

      message_ids = Array(value["statuses"]).filter_map { |status| status["id"].presence }
      if message_ids.present?
        message_tenant = unique_tenant_from_relation(WhatsappMessage.where(wa_message_id: message_ids))
        return message_tenant if message_tenant

        campaign_message_tenant = unique_tenant_from_relation(WhatsappCampaignMessage.where(external_message_id: message_ids))
        return campaign_message_tenant if campaign_message_tenant
      end

      template_id = value["message_template_id"].presence&.to_s
      if template_id.present?
        template_tenant = unique_tenant_from_relation(WhatsappTemplate.where(meta_id: template_id))
        return template_tenant if template_tenant
      end

      nil
    end

    def unique_tenant_from_relation(relation)
      tenant_ids = relation.where.not(tenant_id: nil).distinct.limit(2).pluck(:tenant_id)
      return Tenant.find_by(id: tenant_ids.first) if tenant_ids.one?

      @tenant_resolution_ambiguous = true if tenant_ids.many?
      nil
    end
  end
end
