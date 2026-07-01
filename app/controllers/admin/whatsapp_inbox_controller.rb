class Admin::WhatsappInboxController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_inbox) }
  before_action -> { check_permission!(:manage, :whatsapp_inbox) }, only: [:send_message, :sync_templates]
  before_action :set_conversation, only: [:show, :send_message]
  before_action :set_message, only: [:media]

  def index
    load_inbox
    @page_title = "Atendimento WhatsApp"
    render :index
  end

  def show
    load_inbox
    unread_before = @conversation.unread_count.to_i
    @conversation.mark_read!
    Whatsapp::ThreadBroadcaster.queue_refreshed(@conversation) if unread_before.positive?
    @messages = @conversation.messages.ordered
    load_thread_context
    @page_title = "WhatsApp · #{@conversation.display_name}"
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

  def send_message
    @integration = WhatsappBusinessIntegration.current(current_tenant)
    body = params[:body].to_s.strip
    template_name = params[:template_name].to_s.strip
    media_file = params[:media_file]
    return_path = safe_return_path(params[:return_to])

    if template_name.present? && media_file.present?
      return respond_send_message_error("Escolha entre modelo aprovado ou arquivo.", return_path:)
    end

    if template_name.present? && body.present?
      return respond_send_message_error("Modelos aprovados não aceitam texto livre nessa resposta.", return_path:)
    end

    if template_name.present?
      message = build_outbound(msg_type: "template", template_name: template_name, body: template_body(template_name))
    elsif media_file.present?
      media_validation = Whatsapp::MediaSupport.validation_for(media_file)
      return respond_send_message_error(media_validation[:error], return_path:) unless media_validation[:ok]

      message = build_outbound(msg_type: media_validation[:type], body: body, media_url: nil)
    elsif body.present?
      message = build_outbound(msg_type: "text", body: body)
    else
      return respond_send_message_error("Escreva uma mensagem ou envie um arquivo.", return_path:)
    end

    message.media_file.attach(media_file) if media_file.present?
    message.save!
    @conversation.touch_last_message!(message)
    Whatsapp::ThreadBroadcaster.message_created(message)
    Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
    LeadActivity.log!(lead: @conversation.lead, kind: "whatsapp_out", metadata: { body: message.preview, by: current_admin_user&.name }) if @conversation.lead_id
    @messages = @conversation.messages.ordered
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
    result = Whatsapp::SyncTemplatesJob.perform_now(current_tenant.id)
    if result.is_a?(Hash) && result[:ok]
      redirect_to admin_whatsapp_conversations_path, notice: "#{result[:synced]} modelos sincronizados."
    else
      redirect_to admin_whatsapp_conversations_path, alert: "Não foi possível sincronizar os modelos. Verifique a conexão do WhatsApp."
    end
  end

  private

  def load_inbox
    @focus_mode = params[:workspace] == "focus"
    @integration = WhatsappBusinessIntegration.current(current_tenant)
    @conversations = conversation_scope.recent.limit(200)
    @templates = current_tenant.whatsapp_templates.approved.ordered
    @conversation_count = @conversations.size
    @total_unread = conversation_scope.unread.sum(:unread_count)
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
    @messages.maximum(:updated_at)&.iso8601(6)
  end

  def thread_context_html
    render_to_string(
      partial: "admin/whatsapp_inbox/thread_context",
      formats: [:html],
      locals: @thread_context_locals
    )
  end

end
