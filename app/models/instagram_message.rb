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

  def notify_conversation
    ActionCable.server.broadcast(LeadConversationChannel.stream_name(lead), { refresh: true })
  rescue StandardError => error
    Rails.logger.warn("[Instagram thread] broadcast unavailable class=#{error.class}")
  end
end
