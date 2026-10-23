class InstagramMessage < ApplicationRecord
  belongs_to :lead
  belongs_to :sent_by_admin_user, class_name: "AdminUser", optional: true

  after_create_commit :notify_conversation

  validates :message_id, :occurred_at, presence: true
  validates :direction, inclusion: { in: %w[inbound outbound] }

  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }
  scope :chronological, -> { order(:occurred_at, :id) }

  def inbound? = direction == "inbound"

  def outbound? = direction == "outbound"
  private

  def notify_unread
    lead.tenant.admin_users.active.includes(:profile).find_each do |user|
      next unless user.can?(:view, :leads) && Lead.accessible_to_admin(user, tenant: lead.tenant).exists?(id: lead.id)

      InAppNotification.notify!(admin_user: user, kind: "instagram_message", title: "Nova mensagem no Instagram",
        url: Rails.application.routes.url_helpers.admin_lead_path(lead, anchor: "lead-instagram-thread"),
        metadata: { lead_id: lead.id, instagram_message_id: id })
    end
  rescue StandardError => error
    Rails.logger.warn("[Instagram unread] notification unavailable class=#{error.class}")
  end

  def notify_conversation
    notify_unread if inbound?
    ActionCable.server.broadcast(LeadConversationChannel.stream_name(lead), { refresh: true })
  rescue StandardError => error
    Rails.logger.warn("[Instagram thread] broadcast unavailable class=#{error.class}")
  end
end
