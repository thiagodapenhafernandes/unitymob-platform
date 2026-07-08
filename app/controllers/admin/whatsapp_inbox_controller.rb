class Admin::WhatsappInboxController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_inbox) }
  MESSAGE_TOOL_ACTIONS = %i[react toggle_pin toggle_star forward_message add_to_notes hide_message].freeze
  # Janela do thread: últimas N mensagens em ordem cronológica (conversas longas
  # não carregam o histórico inteiro a cada clique).
  THREAD_HISTORY_LIMIT = 300
  # Fila é filtrada/buscada client-side (wa-queue opera sobre o DOM): reduzir o
  # limite esconde conversas da busca — por isso configurável, default 200.
  DEFAULT_QUEUE_LIMIT = 200
  before_action -> { check_permission!(:manage, :whatsapp_inbox) }, only: [:send_message, :sync_templates, *MESSAGE_TOOL_ACTIONS]
  before_action :set_conversation, only: [:show, :send_message, *MESSAGE_TOOL_ACTIONS]
  before_action :set_message, only: [:media]

  def index
    load_inbox
    @page_title = "Atendimento WhatsApp"
    render :index
  end

  def show
    if turbo_frame_request?
      load_thread_dependencies
    else
      load_inbox
    end

    unread_before = @conversation.unread_count.to_i
    @conversation.mark_read!
    Whatsapp::ThreadBroadcaster.queue_refreshed(@conversation) if unread_before.positive?
    load_thread_messages
    load_thread_context
    @page_title = "WhatsApp · #{@conversation.display_name}"

    if turbo_frame_request?
      return render html: helpers.turbo_frame_tag("wa-thread") {
        render_to_string(
          partial: "admin/whatsapp_inbox/thread_panel",
          formats: [:html],
          locals: thread_panel_locals
        )
      }.html_safe
    end

    render :index
  end

  def media
    return head :not_found unless @message.media?

    if @message.media_file.attached?
      disposition = @message.media_inline? ? "inline" : "attachment"
      return redirect_to rails_blob_path(@message.media_file, disposition: disposition)
    end

    return head :not_found if @message.media_url.blank?

    download = Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(current_tenant)).download_media(@message.media_url)
    return head :bad_gateway unless download[:ok]

    disposition = @message.media_inline? ? "inline" : "attachment"
    send_data download[:body],
              filename: @message.media_name.presence || inferred_media_filename(@message),
              type: download[:content_type].presence || "application/octet-stream",
              disposition: disposition
  end

  # ===== Menu de mensagem (Responder ja vive no send_message via reply_to_id) =====

  def react
    message = @conversation.messages.find(params[:message_id])
    return render json: { ok: false, error: "Aguarde a mensagem ser entregue para reagir." }, status: :unprocessable_entity if message.wa_message_id.blank?

    emoji = params[:emoji].to_s.strip
    integration = WhatsappBusinessIntegration.current(current_tenant)
    client = Whatsapp::CloudClient.new(integration)
    result = client.send_reaction(to: @conversation.cloud_recipient, message_id: message.wa_message_id, emoji: emoji)
    return render json: { ok: false, error: result[:error].to_s.presence || "Não foi possível reagir." }, status: :unprocessable_entity unless result[:ok]

    message.update!(agent_reaction: emoji.presence)
    Whatsapp::ThreadBroadcaster.message_updated(message)
    render json: { ok: true }
  end

  def toggle_pin
    message = @conversation.messages.find(params[:message_id])
    message.update!(pinned_at: message.pinned_at ? nil : Time.current)
    Whatsapp::ThreadBroadcaster.message_updated(message)
    render json: { ok: true, pinned: message.pinned_at.present?, snippet: message.preview.to_s.truncate(90) }
  end

  def toggle_star
    message = @conversation.messages.find(params[:message_id])
    message.update!(starred_at: message.starred_at ? nil : Time.current)
    Whatsapp::ThreadBroadcaster.message_updated(message)
    render json: { ok: true, starred: message.starred_at.present? }
  end

  def forward_message
    source = @conversation.messages.find(params[:message_id])
    target = current_tenant.whatsapp_conversations.find(params[:target_conversation_id])

    forwarded = target.messages.new(
      direction: "outbound",
      status: "pending",
      admin_user: current_admin_user,
      msg_type: source.msg_type == "template" ? "text" : source.msg_type,
      body: source.body,
      media_url: source.media_url
    )
    forwarded.media_file.attach(source.media_file.blob) if source.media_file.attached?
    forwarded.save!
    target.touch_last_message!(forwarded)
    Whatsapp::ThreadBroadcaster.message_created(forwarded)
    Whatsapp::SendMessageJob.dispatch(forwarded.id, tenant_id: forwarded.tenant_id)

    render json: { ok: true, target_name: target.display_name }
  end

  def add_to_notes
    message = @conversation.messages.find(params[:message_id])
    lead = @conversation.lead
    return render json: { ok: false, error: "Conversa sem lead vinculado — vincule um lead primeiro." }, status: :unprocessable_entity if lead.blank?

    stamp = "#{message.outbound? ? 'Atendente' : @conversation.display_name} · WhatsApp · #{I18n.l(message.created_at, format: '%d/%m %H:%M')}"
    entry = "— #{message.preview.to_s.strip} (#{stamp})"
    lead.update(notes: [lead.notes.presence, entry].compact.join("
"))
    LeadActivity.log!(lead: lead, kind: "note", metadata: { body: message.preview.to_s.truncate(200), source: "whatsapp_message" })
    render json: { ok: true }
  end

  def hide_message
    message = @conversation.messages.find(params[:message_id])
    message.update!(hidden_at: Time.current)
    render json: { ok: true }
  end

  def send_message
    @integration = WhatsappBusinessIntegration.current(current_tenant)
    body = params[:body].to_s.strip
    template_name = params[:template_name].to_s.strip
    media_file = params[:media_file]
    return_path = safe_return_path(params[:return_to])

    # Apresentação via composer: o picker preenche o textarea e envia o card_id
    # num hidden; o envio ganha o carimbo de auditoria (regra de ouro preservada:
    # o corpo é o texto do composer + o pipeline é o número da empresa).
    presentation_card = if params[:presentation_card_id].present? && @integration&.presentation_enabled?
      PresentationCard.available_for(current_admin_user).find_by(id: params[:presentation_card_id])
    end

    # Gate "exigir apresentação": bloqueia envio livre (texto, modelo ou mídia),
    # mas NUNCA o próprio envio de apresentação (card presente).
    if presentation_card.nil? && presentation_pending?(@integration)
      return respond_send_message_error("Envie sua apresentação primeiro — escolha um cartão no painel ao lado.", return_path:)
    end

    if template_name.present? && media_file.present?
      return respond_send_message_error("Escolha entre modelo aprovado ou arquivo.", return_path:)
    end

    if template_name.present? && body.present?
      return respond_send_message_error("Modelos aprovados não aceitam texto livre nessa resposta.", return_path:)
    end

    if template_name.present?
      message = build_outbound(msg_type: "template", template_name: template_name, body: template_body(template_name))
    elsif media_file.present?
      media_validation = Whatsapp::MediaSupport.validation_for(media_file, allow_convertible: true)
      return respond_send_message_error(media_validation[:error], return_path:) unless media_validation[:ok]

      message = build_outbound(msg_type: media_validation[:type], body: body, media_url: nil)
    elsif body.present?
      # Apresentação com foto: texto vira legenda do avatar (uma única mensagem).
      if presentation_card && presentation_photo_available?(presentation_card)
        message = build_outbound(msg_type: "image", body: body)
        message.media_file.attach(current_admin_user.avatar.blob)
      else
        message = build_outbound(msg_type: "text", body: body)
      end
    else
      return respond_send_message_error("Escreva uma mensagem ou envie um arquivo.", return_path:)
    end

    # Responder (citação): amarra a mensagem citada; a Meta renderiza o quote
    if params[:reply_to_id].present? && message.respond_to?(:context_wa_message_id=)
      replied = @conversation.messages.find_by(id: params[:reply_to_id])
      message.context_wa_message_id = replied.wa_message_id if replied&.wa_message_id.present?
    end

    message.presentation_card = presentation_card if presentation_card
    if media_file.present?
      # identify: false para audio — o sniff do Rails reclassifica m4a/ogg como
      # video/mp4 e dispara PreviewImageJob de frame em arquivo sem stream de video
      message.media_file.attach(
        io: media_file.tempfile,
        filename: media_file.original_filename,
        content_type: media_validation[:content_type],
        identify: media_validation[:type] != "audio"
      )
    end
    message.save!
    @conversation.touch_last_message!(message)
    Whatsapp::ThreadBroadcaster.message_created(message)
    Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
    if presentation_card
      log_presentation_sent(presentation_card, message.msg_type == "image" ? "image" : "text")
    end
    LeadActivity.log!(lead: @conversation.lead, kind: "whatsapp_out", metadata: { body: message.preview, by: current_admin_user&.name }) if @conversation.lead_id
    load_thread_messages
    load_thread_context

    respond_to do |format|
      format.html { redirect_to(return_path || admin_whatsapp_conversation_path(@conversation)) }
      format.json do
        render json: serialize(message).merge(
          ok: true,
          status_cursor: thread_status_cursor,
          context_html: thread_context_html,
          queue: serialize_conversation(@conversation)
        )
      end
    end
  end

  def sync_templates
    # Em background: a chamada à Meta pode demorar/travar — o request não espera.
    Whatsapp::SyncTemplatesJob.perform_later(current_tenant.id)
    redirect_to admin_whatsapp_conversations_path,
                notice: "Sincronização de modelos iniciada — os modelos aparecem no ⚡ em instantes."
  end

  private

  def load_inbox
    @focus_mode = params[:workspace] == "focus"
    @integration = WhatsappBusinessIntegration.current(current_tenant)
    @conversations = conversation_scope.recent.limit(queue_limit)
    @templates = current_tenant.whatsapp_templates.approved.ordered
    @conversation_count = @conversations.size
    @total_unread = conversation_scope.unread.sum(:unread_count)
  end

  def load_thread_dependencies
    @focus_mode = params[:workspace] == "focus"
    @integration = WhatsappBusinessIntegration.current(current_tenant)
    @templates = current_tenant.whatsapp_templates.approved.ordered
  end

  # Últimas mensagens com anexos pré-carregados (sem N+1 de ActiveStorage);
  # .last sobre a relação ordenada preserva a ordem cronológica do thread.
  def load_thread_messages
    @messages = @conversation.messages.visible.ordered.with_attached_media_file.last(THREAD_HISTORY_LIMIT)
    @quoted_messages = quoted_messages_for(@messages)
  end

  # Mensagens citadas (Responder) resolvidas em 1 query, dentro da mesma conversa.
  def quoted_messages_for(messages)
    context_ids = messages.filter_map { |message| message.try(:context_wa_message_id).presence }.uniq
    return {} if context_ids.empty?

    @conversation.messages.where(wa_message_id: context_ids).index_by(&:wa_message_id)
  end

  def queue_limit
    limit = ENV["WA_INBOX_QUEUE_LIMIT"].to_i
    limit.positive? ? limit : DEFAULT_QUEUE_LIMIT
  end

  def load_thread_context
    @thread_context_locals = Whatsapp::ThreadContextSnapshot.new(
      conversation: @conversation,
      messages: @messages,
      focus_mode: @focus_mode,
      tenant: current_tenant
    ).to_h.merge(
      can_manage_comercial: can?(:manage, :comercial)
    )
  end

  def conversation_scope
    base = current_tenant.whatsapp_conversations.includes(:assigned_admin_user, lead: { lead_labelings: :lead_label })
    ids = visible_owner_ids(:whatsapp_inbox)
    return base if ids.nil?

    base.left_joins(:lead).where(
      "whatsapp_conversations.assigned_admin_user_id IN (:ids) OR leads.admin_user_id IN (:ids)",
      ids: ids
    )
  end

  def set_conversation
    @conversation = conversation_scope.find(params[:id])
  end

  def set_message
    @conversation = conversation_scope.find(params[:id])
    @message = @conversation.messages.find(params[:message_id])
  end

  def build_outbound(attrs)
    @conversation.messages.new({ direction: "outbound", status: "pending", admin_user: current_admin_user }.merge(attrs))
  end

  # "Exigir apresentação" com retroatividade (cutoff) — lógica no model.
  def presentation_pending?(integration)
    integration&.presentation_required_for?(@conversation, current_admin_user) || false
  end

  # Foto no envio de apresentação: só com o toggle da conta ligado, cartão com
  # use_photo e avatar válido no perfil (sem avatar cai para texto).
  def presentation_photo_available?(card)
    @integration&.allow_photo_presentation? && card.use_photo? &&
      current_admin_user.avatar.attached? &&
      Whatsapp::MediaSupport.validation_for(current_admin_user.avatar.blob)[:ok]
  end

  # A trilha consultável é a própria WhatsappMessage (presentation_card_id +
  # admin_user + conversa + created_at), com ou sem lead. O LeadActivity entra
  # apenas como evento de timeline quando há lead vinculado.
  def log_presentation_sent(card, format)
    return unless @conversation.lead_id

    LeadActivity.log!(
      lead: @conversation.lead,
      kind: "presentation_sent",
      metadata: { admin_user_id: current_admin_user.id, card_id: card.id, format: format }
    )
  end

  def template_body(name)
    current_tenant.whatsapp_templates.find_by(name: name)&.body
  end

  def serialize(message)
    media_url = media_url_for(message)
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
      html: render_to_string(
        partial: "admin/whatsapp_inbox/message_bubble",
        formats: [:html],
        locals: {
          message:,
          media_url:,
          previous_message: previous_message,
          next_message: next_message,
          compact_mode: @focus_mode
        }
      )
    }
  end

  def media_url_for(message)
    return message_media_admin_whatsapp_conversation_path(@conversation || message.whatsapp_conversation, message_id: message.id) if message.media?
    return rails_blob_path(message.media_file, disposition: "inline") if message.media_file.attached?

    nil
  end

  def inferred_media_filename(message)
    extension = Rack::Mime::MIME_TYPES.invert[message.media_content_type.to_s]&.delete_prefix(".")
    base = [message.msg_type.presence || "media", message.id].compact.join("-")
    extension.present? ? "#{base}.#{extension}" : base
  end

  def safe_return_path(value)
    path = value.to_s
    return nil if path.blank?
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//")

    path
  end

  def respond_send_message_error(message, return_path:)
    respond_to do |format|
      format.html { redirect_to(return_path || admin_whatsapp_conversation_path(@conversation), alert: message) }
      format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
    end
  end

  def serialize_conversation(conversation)
    {
      id: conversation.id,
      html: render_to_string(
        partial: "admin/whatsapp_inbox/conversation_item",
        formats: [:html],
        locals: {
          conv: conversation,
          active: @conversation.present? && @conversation.id == conversation.id,
          focus_mode: @focus_mode,
          compact_mode: true
        }
      )
    }
  end

  def thread_status_cursor
    # @messages é Array (janela .last) — mesmo cálculo do _thread_workspace
    @messages.map(&:updated_at).compact.max&.iso8601(6)
  end

  def thread_context_html
    render_to_string(
      partial: "admin/whatsapp_inbox/thread_context",
      formats: [:html],
      locals: @thread_context_locals
    )
  end

  def thread_panel_locals
    {
      conversation: @conversation,
      messages: @messages,
      quoted_messages: @quoted_messages,
      thread_context_locals: @thread_context_locals,
      focus_mode: @focus_mode,
      integration: @integration,
      templates: @templates,
      current_thread_url: @focus_mode ? admin_whatsapp_conversation_path(@conversation, workspace: "focus") : admin_whatsapp_conversation_path(@conversation),
      thread_compact: true,
      composer_compact: true
    }
  end

end
