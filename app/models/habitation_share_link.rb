class HabitationShareLink < ApplicationRecord
  COOKIE_KEY = :habitation_share_token
  BROKER_PAGE_TOKEN_PREFIX = "broker-page-".freeze
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
    active.where(habitation: habitation, admin_user: admin_user).where.not("token LIKE ?", "#{BROKER_PAGE_TOKEN_PREFIX}%")
          .order(expires_at: :desc)
          .first || create!(habitation: habitation, admin_user: admin_user)
  end

  def self.expiration_days(tenant: Current.tenant)
    raw_value = Setting.tenant_get(EXPIRATION_SETTING_KEY, DEFAULT_EXPIRATION_DAYS.to_s, tenant: tenant).presence || DEFAULT_EXPIRATION_DAYS.to_s
    raw_value.to_i.clamp(MIN_EXPIRATION_DAYS, MAX_EXPIRATION_DAYS)
  end

  def self.for_broker_page(broker:, habitations:)
    properties = habitations.to_a
    raise ArgumentError, "Imóveis de outra conta" unless properties.all? { |property| property.tenant_id == broker.tenant_id }

    links = active.where(admin_user: broker, habitation_id: properties.map(&:id))
      .where("token LIKE ?", "#{BROKER_PAGE_TOKEN_PREFIX}%")
      .order(expires_at: :desc).to_a.group_by(&:habitation_id).transform_values(&:first)
    properties.each do |property|
      links[property.id] ||= create!(habitation: property, admin_user: broker,
        token: "#{BROKER_PAGE_TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(24)}")
    end
    links
  end

  def self.expiration_period(tenant: Current.tenant)
    expiration_days(tenant: tenant).days
  end

  def expired?
    expires_at <= Time.current
  end

  def broker_page?
    token.to_s.start_with?(BROKER_PAGE_TOKEN_PREFIX)
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
    self.expires_at ||= self.class.expiration_period(tenant: habitation&.tenant || admin_user&.tenant || Current.tenant).from_now
  end
end
