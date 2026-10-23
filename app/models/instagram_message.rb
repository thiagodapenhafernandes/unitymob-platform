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
    user = lead.admin_user
    if user.nil?
      integration = UserMetaIntegration.owned_by_tenant(lead.tenant_id).joins(:meta_facebook_pages)
        .find_by(meta_facebook_pages: { instagram_id: lead.instagram_account_id, instagram_enabled: true })
      user = integration&.admin_user
    end
    return unless user&.active? && user.tenant_id == lead.tenant_id && user.can?(:view, :leads)
    return unless Lead.accessible_to_admin(user, tenant: lead.tenant).exists?(id: lead.id)

    previous_direction = lead.instagram_messages.where("occurred_at < ? OR (occurred_at = ? AND id < ?)", occurred_at, occurred_at, id)
      .order(occurred_at: :desc, id: :desc).pick(:direction)
    InAppNotification.notify!(admin_user: user, kind: "instagram_message", title: "Nova mensagem no Instagram", body: body.presence&.truncate(160),
      url: Rails.application.routes.url_helpers.admin_lead_path(lead, anchor: "lead-instagram-thread"),
      metadata: { lead_id: lead.id, instagram_message_id: id, sender_name: lead.display_name,
        event: (previous_direction == "outbound" ? "message_reply" : "instagram_message") })
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
