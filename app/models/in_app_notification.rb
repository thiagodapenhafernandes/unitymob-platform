# Notificação interna (sino + toast em tempo real). Push fica com Notifications::PushDispatcher.
class InAppNotification < ApplicationRecord
  include TenantScoped

  belongs_to :admin_user

  validates :kind, :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def self.stream_name(admin_user_id) = "in_app_notifications:#{admin_user_id}"

  def self.unread_count_for(admin_user) = unread.where(admin_user_id: admin_user.id).count

  def self.visible_for(user, tenant)
    scope = where(admin_user_id: user.id, tenant_id: tenant.id)
    direct = scope.where(kind: "instagram_message")
    other = scope.where.not(kind: "instagram_message")
    return other unless user.can?(:view, :leads)

    visible_leads = Lead.accessible_to_admin(user, tenant: tenant).select("leads.id::text")
    other.or(direct.where("metadata ->> 'lead_id' IN (?)", visible_leads))
  end

  def self.title_count_for(user, tenant)
    visible_for(user, tenant).unread.count
  end

  def self.notify_whatsapp_message!(conversation, message)
    user = conversation.tenant.admin_users.active.find_by(id: conversation.alert_recipient_id)
    return unless user&.can?(:view, :whatsapp_inbox)

    notify!(admin_user: user, kind: "whatsapp_message", title: "Nova mensagem no WhatsApp",
      url: Rails.application.routes.url_helpers.admin_whatsapp_conversation_path(conversation),
      metadata: { conversation_id: conversation.id, whatsapp_message_id: message.id })
  rescue StandardError => error
    Rails.logger.warn("[WhatsApp unread] notification unavailable class=#{error.class}")
  end

  def self.invalidate_title!(tenant_id)
    ActionCable.server.broadcast("unread_title:#{tenant_id}", { event: "unread_changed" })
  rescue StandardError => error
    Rails.logger.warn("[Unread title] broadcast unavailable class=#{error.class}")
  end

  def self.notify!(admin_user:, kind:, title:, body: nil, url: nil, metadata: {})
    return if admin_user.blank?

    notification = create!(tenant_id: admin_user.tenant_id, admin_user: admin_user, kind: kind, title: title, body: body, url: url, metadata: metadata)
    ActionCable.server.broadcast(stream_name(admin_user.id), notification.broadcast_payload)
    notification
  rescue => e
    Rails.logger.warn("[InAppNotification] falha ao notificar admin_user=#{admin_user&.id}: #{e.class}: #{e.message}")
    nil
  end

  # Abrir a conversa (por qualquer caminho) dá as notificações dela como lidas e avisa o sino em tempo real.
  def self.mark_conversation_read!(admin_user, conversation_id)
    scope = unread.where(admin_user_id: admin_user.id).where("metadata ->> 'conversation_id' = ?", conversation_id.to_s)
    ids = scope.pluck(:id)
    return if ids.empty?

    scope.update_all(read_at: Time.current, updated_at: Time.current)
    broadcast_event!(admin_user.id, event: "read", ids: ids, unread_count: unread_count_for(admin_user))
  end

  # Evento efêmero (sem registro no sino): ex.: tocar o som quando chega mensagem do cliente.
  def self.broadcast_event!(admin_user_id, payload)
    ActionCable.server.broadcast(stream_name(admin_user_id), payload) if admin_user_id.present?
  end

  def broadcast_payload
    {
      id: id, kind: kind, title: title, body: body, url: url, created_at: created_at.iso8601,
      unread_count: self.class.unread_count_for(admin_user)
    }
  end
end
