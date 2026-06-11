class SeoPageVisit < ApplicationRecord
  BOT_USER_AGENT = /(bot|crawl|spider|slurp|bingpreview|facebookexternalhit|whatsapp|telegrambot|linkedinbot|preview)/i

  belongs_to :seo_setting

  validates :visitor_hash, :path, :visited_on, :first_seen_at, :last_seen_at, presence: true
  validates :visits_count, numericality: { only_integer: true, greater_than: 0 }

  class << self
    def record!(seo_setting, request)
      return if seo_setting.blank? || bot_request?(request)

      now = Time.current
      attrs = identity_attributes(request)
      visit = create_or_find_by!(
        seo_setting: seo_setting,
        visitor_hash: attrs[:visitor_hash],
        visited_on: now.to_date
      ) do |record|
        record.session_hash = attrs[:session_hash]
        record.user_agent_hash = attrs[:user_agent_hash]
        record.path = request.fullpath.to_s.first(500)
        record.first_seen_at = now
        record.last_seen_at = now
        record.visits_count = 1
      end

      return visit if visit.previously_new_record?

      visit.increment!(:visits_count, 1, touch: false)
      visit.update_columns(last_seen_at: now, updated_at: now)
      visit
    rescue ActiveRecord::RecordNotUnique
      retry
    rescue => e
      Rails.logger.warn("[SeoPageVisit] #{e.class}: #{e.message}")
      nil
    end

    def unique_visitors_since(date)
      where(visited_on: date..).distinct.count(:visitor_hash)
    end

    private

    def identity_attributes(request)
      user_agent = request.user_agent.to_s
      session_id = safe_session_id(request)
      visitor_source = [
        request.remote_ip,
        user_agent,
        session_id.presence || "no-session"
      ].join("|")

      {
        visitor_hash: hmac(visitor_source),
        session_hash: session_id.present? ? hmac(session_id) : nil,
        user_agent_hash: user_agent.present? ? hmac(user_agent) : nil
      }
    end

    def safe_session_id(request)
      request.session.id&.public_id
    rescue
      nil
    end

    def bot_request?(request)
      request.user_agent.to_s.match?(BOT_USER_AGENT)
    end

    def hmac(value)
      secret = Rails.application.secret_key_base.to_s
      OpenSSL::HMAC.hexdigest("SHA256", secret, value.to_s)
    end
  end
end
