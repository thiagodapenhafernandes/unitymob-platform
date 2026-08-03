class OperationalUserSession < ApplicationRecord
  include TenantScoped

  belongs_to :admin_user
  has_many :events,
           class_name: "OperationalUserEvent",
           dependent: :destroy,
           inverse_of: :operational_user_session

  validates :token, presence: true, uniqueness: true
  validates :started_at, :last_seen_at, presence: true
  validates :duration_seconds, :events_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :admin_user_tenant_consistency

  before_validation :set_defaults

  scope :recent, -> { order(last_seen_at: :desc, id: :desc) }
  scope :active_since, ->(time) { where("last_seen_at >= ?", time) }

  def record_event!(occurred_at:)
    elapsed = [occurred_at.to_i - started_at.to_i, 0].max
    update_columns(
      last_seen_at: occurred_at,
      duration_seconds: elapsed,
      events_count: events_count.to_i + 1,
      updated_at: Time.current
    )
  end

  def duration_label
    total = duration_seconds.to_i
    hours = total / 3600
    minutes = (total % 3600) / 60

    return "#{hours}h #{minutes}min" if hours.positive?
    return "#{minutes}min" if minutes.positive?

    "#{total}s"
  end

  def closed?
    ended_at.present?
  end

  private

  def set_defaults
    now = Time.current
    self.token ||= SecureRandom.uuid
    self.started_at ||= now
    self.last_seen_at ||= started_at || now
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def admin_user_tenant_consistency
    errors.add(:admin_user, "não pertence à conta") if admin_user && admin_user.tenant_id != tenant_id
  end
end
