class HabitationShareLink < ApplicationRecord
  COOKIE_KEY = :habitation_share_token
  DEFAULT_EXPIRATION_DAYS = 30
  MIN_EXPIRATION_DAYS = 1
  MAX_EXPIRATION_DAYS = 365
  EXPIRATION_SETTING_KEY = "lead_share_tracking_days"

  belongs_to :habitation
  belongs_to :admin_user

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where('expires_at > ?', Time.current) }

  before_validation :ensure_token, on: :create
  before_validation :ensure_expires_at, on: :create

  def self.create_or_reuse_for(habitation:, admin_user:)
    active.where(habitation: habitation, admin_user: admin_user)
          .order(expires_at: :desc)
          .first || create!(habitation: habitation, admin_user: admin_user)
  end

  def self.expiration_days
    raw_value = Setting.get(EXPIRATION_SETTING_KEY, DEFAULT_EXPIRATION_DAYS.to_s).presence || DEFAULT_EXPIRATION_DAYS.to_s
    raw_value.to_i.clamp(MIN_EXPIRATION_DAYS, MAX_EXPIRATION_DAYS)
  end

  def self.expiration_period
    expiration_days.days
  end

  def expired?
    expires_at <= Time.current
  end

  def register_click!
    update_columns(last_clicked_at: Time.current, clicks_count: clicks_count.to_i + 1)
  end

  private

  def ensure_token
    return if token.present?

    self.token = loop do
      candidate = SecureRandom.urlsafe_base64(24).tr('lIO0', 'sxyz')
      break candidate unless self.class.exists?(token: candidate)
    end
  end

  def ensure_expires_at
    self.expires_at ||= self.class.expiration_period.from_now
  end
end
