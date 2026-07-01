class WhatsappConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = authorized_conversation
    reject unless conversation

    stream_from stream_name(conversation, focus_mode: focus_mode?)
  end

  private

  def authorized_conversation
    conversation_id = params[:conversation_id].to_i
    return if conversation_id <= 0
    return unless current_admin_user&.can?(:view, :whatsapp_inbox)

    scope = WhatsappConversation.where(id: conversation_id)
    if current_admin_user.system_admin?
      scope.first
    else
      scope.find_by(tenant_id: current_admin_user.tenant_id)
    end
  end

  def stream_name(conversation, focus_mode:)
    Whatsapp::ThreadBroadcaster.stream_name(conversation, focus_mode: focus_mode)
  end

  def focus_mode?
    ActiveModel::Type::Boolean.new.cast(params[:focus_mode])
  end
end
