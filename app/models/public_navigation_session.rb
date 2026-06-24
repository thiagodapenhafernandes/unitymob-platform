class PublicNavigationSession < ApplicationRecord
  COOKIE_KEY = "unitymob_public_navigation".freeze

  belongs_to :lead, optional: true
  has_many :events, class_name: "PublicNavigationEvent", dependent: :destroy

  validates :token, presence: true, uniqueness: true
  validates :first_seen_at, :last_seen_at, presence: true

  before_validation :set_defaults

  scope :recent, -> { order(last_seen_at: :desc) }

  def self.find_or_create_for_token(token, request:)
    clean_token = token.to_s.strip.presence || SecureRandom.uuid

    find_or_initialize_by(token: clean_token).tap do |session|
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

    update!(lead: lead, last_seen_at: Time.current)
    events.where(lead_id: nil).update_all(lead_id: lead.id, updated_at: Time.current)
  end

  private

  def set_defaults
    self.token ||= SecureRandom.uuid
    self.first_seen_at ||= Time.current
    self.last_seen_at ||= Time.current
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
