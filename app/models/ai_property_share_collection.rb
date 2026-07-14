class AiPropertyShareCollection < ApplicationRecord
  include TenantScoped

  belongs_to :admin_user
  has_many :items, class_name: "AiPropertyShareItem", dependent: :destroy
  has_many :habitations, through: :items
  has_many :audit_events, class_name: "AiPropertyShareAuditEvent", dependent: :destroy

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :broker_belongs_to_tenant

  scope :active, -> { where("expires_at > ?", Time.current) }
  before_validation :set_defaults, on: :create

  def record!(event_type, lead: nil, habitation: nil, admin_user: nil, metadata: {})
    audit_events.create!(tenant:, event_type:, lead:, habitation:, admin_user:, metadata: metadata.compact)
  end

  private

  def set_defaults
    self.token ||= SecureRandom.urlsafe_base64(24)
    self.expires_at ||= PropertySetting.instance(tenant:).ai_property_search_share_expiration_days.days.from_now
  end

  def broker_belongs_to_tenant
    errors.add(:admin_user, "deve pertencer ao mesmo Tenant") if admin_user && admin_user.tenant_id != tenant_id
  end
end
