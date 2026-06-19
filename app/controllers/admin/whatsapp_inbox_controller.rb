class Admin::WhatsappInboxController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_inbox) }
  before_action -> { check_permission!(:manage, :whatsapp_inbox) }, only: [:send_message, :assign_lead, :sync_templates]
  before_action :set_conversation, only: [:show, :send_message, :assign_lead, :messages]

  def index
    load_inbox
    @page_title = "Atendimento WhatsApp"
    render :index
  end

  def show
    load_inbox
    @conversation.mark_read!
    @messages = @conversation.messages.ordered
    @page_title = "WhatsApp · #{@conversation.display_name}"
    render :index
  end

  # Polling leve — devolve as mensagens novas (após :after) em JSON.
  def messages
    after = params[:after].to_i
    scope = @conversation.messages.ordered
    scope = scope.where("id > ?", after) if after.positive?
    render json: scope.map { |m| serialize(m) }
  end

  def send_message
    @integration = WhatsappBusinessIntegration.current
    body = params[:body].to_s.strip
    template_name = params[:template_name].to_s.strip

    if template_name.present?
      message = build_outbound(msg_type: "template", template_name: template_name, body: template_body(template_name))
    elsif body.present?
      message = build_outbound(msg_type: "text", body: body)
    else
      return redirect_to admin_whatsapp_conversation_path(@conversation), alert: "Escreva uma mensagem."
    end

    message.save!
    @conversation.touch_last_message!(message)
    Whatsapp::SendMessageJob.perform_later(message.id)
    LeadActivity.log!(lead: @conversation.lead, kind: "whatsapp_out", metadata: { body: message.preview, by: current_admin_user&.name }) if @conversation.lead_id

    redirect_to admin_whatsapp_conversation_path(@conversation)
  end

  def assign_lead
    lead = Lead.find_by(id: params[:lead_id])
    @conversation.update(lead: lead) if lead
    redirect_to admin_whatsapp_conversation_path(@conversation), notice: "Conversa vinculada ao lead."
  end

  def sync_templates
    result = Whatsapp::SyncTemplatesJob.perform_now
    if result.is_a?(Hash) && result[:ok]
      redirect_to admin_whatsapp_conversations_path, notice: "#{result[:synced]} modelos sincronizados."
    else
      redirect_to admin_whatsapp_conversations_path, alert: "Não foi possível sincronizar os modelos. Verifique a conexão do WhatsApp."
    end
  end

  private

  def load_inbox
    @integration = WhatsappBusinessIntegration.current
    @conversations = conversation_scope.recent.limit(200)
    @templates = WhatsappTemplate.approved.ordered
    @total_unread = conversation_scope.unread.sum(:unread_count)
  end

  def conversation_scope
    base = WhatsappConversation.includes(:lead, :assigned_admin_user)
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

  def build_outbound(attrs)
    @conversation.messages.new({ direction: "outbound", status: "pending", admin_user: current_admin_user }.merge(attrs))
  end

  def template_body(name)
    WhatsappTemplate.find_by(name: name)&.body
  end

  def serialize(message)
    {
      id: message.id,
      direction: message.direction,
      body: message.body,
      type: message.msg_type,
      status: message.status,
      at: message.created_at.strftime("%H:%M")
    }
  end
end
