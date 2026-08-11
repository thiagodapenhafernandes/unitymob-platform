class PublicNavigationSession < ApplicationRecord
  COOKIE_KEY = "unitymob_public_navigation".freeze

  belongs_to :tenant, optional: true
  belongs_to :lead, optional: true
  has_many :events, class_name: "PublicNavigationEvent", dependent: :destroy

  validates :token, presence: true, uniqueness: true
  validates :first_seen_at, :last_seen_at, presence: true

  before_validation :set_defaults

  scope :recent, -> { order(last_seen_at: :desc) }

  def self.find_or_create_for_token(token, request:, tenant: Current.tenant)
    clean_token = token.to_s.strip.presence || SecureRandom.uuid
    session = find_by(token: clean_token)
    if session&.tenant_id.present? && tenant&.id.present? && session.tenant_id != tenant.id
      clean_token = SecureRandom.uuid
      session = nil
    end

    (session || new(token: clean_token)).tap do |session|
      session.tenant ||= tenant || session.lead&.tenant
      session.first_seen_at ||= Time.current
      session.last_seen_at = Time.current
      session.user_agent_digest ||= Digest::SHA256.hexdigest(request.user_agent.to_s).first(64)
      session.landing_url ||= request.referer.presence || request.original_url
      session.referrer_url ||= request.referer
      session.metadata = session.metadata.to_h.merge(
        "ip_hint" => Digest::SHA256.hexdigest(request.remote_ip.to_s).first(16)
      )
      session.save!
    end
  end

  def link_to_lead!(lead)
    return unless lead

    update!(lead: lead, tenant: tenant || lead.tenant, last_seen_at: Time.current)
    events.where(lead_id: nil).update_all(lead_id: lead.id, tenant_id: lead.tenant_id, updated_at: Time.current)
  end

  private

  def set_defaults
    self.token ||= SecureRandom.uuid
    self.first_seen_at ||= Time.current
    self.last_seen_at ||= Time.current
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
