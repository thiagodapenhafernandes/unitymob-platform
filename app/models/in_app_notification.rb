# Notificação interna (sino + toast em tempo real). Push fica com Notifications::PushDispatcher.
class InAppNotification < ApplicationRecord
  include TenantScoped

  belongs_to :admin_user

  validates :kind, :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def self.stream_name(admin_user_id) = "in_app_notifications:#{admin_user_id}"

  def self.unread_count_for(admin_user) = unread.where(admin_user_id: admin_user.id).count

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
