class TrustedDevice < ApplicationRecord
  STATUSES = {
    "pending" => "Pendente",
    "trusted" => "Confiável",
    "blocked" => "Bloqueado"
  }.freeze

  belongs_to :admin_user
  belongs_to :created_by, class_name: "AdminUser", optional: true

  validates :fingerprint, :status, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :fingerprint, uniqueness: { scope: :admin_user_id }

  scope :recent, -> { order(last_seen_at: :desc, created_at: :desc) }
  scope :pending, -> { where(status: "pending") }
  scope :trusted, -> { where(status: "trusted") }
  scope :blocked, -> { where(status: "blocked") }

  def status_label
    STATUSES[status] || status.to_s.humanize
  end

  def device_label
    [device_type, browser, platform].compact_blank.join(" · ").presence || "Dispositivo não identificado"
  end

  def trust!(actor = nil)
    update!(status: "trusted", trusted_at: Time.current, created_by: actor || created_by)
  end

  def block!(actor = nil)
    update!(status: "blocked", created_by: actor || created_by)
  end
end
