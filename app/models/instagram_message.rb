class InstagramMessage < ApplicationRecord
  belongs_to :lead
  belongs_to :sent_by_admin_user, class_name: "AdminUser", optional: true

  validates :message_id, :occurred_at, presence: true
  validates :direction, inclusion: { in: %w[inbound outbound] }

  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }
  scope :chronological, -> { order(:occurred_at, :id) }

  def inbound? = direction == "inbound"

  def outbound? = direction == "outbound"
end
