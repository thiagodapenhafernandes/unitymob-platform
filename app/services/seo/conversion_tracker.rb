module Seo
  class ConversionTracker
    class << self
      def record!(event_type:, request:, lead: nil, habitation: nil, metadata: {})
        new(event_type: event_type, request: request, lead: lead, habitation: habitation, metadata: metadata).record!
      end
    end

    def initialize(event_type:, request:, lead: nil, habitation: nil, metadata: {})
      @event_type = event_type
      @request = request
      @lead = lead
      @habitation = habitation
      @metadata = metadata || {}
    end

    def record!
      return if AccessControl::TrackerExclusion.excluded?(request)

      event = SeoConversionEvent.create!(
        seo_setting: seo_setting,
        marketing_campaign: marketing_campaign,
        lead: lead,
        habitation: habitation,
        event_type: event_type,
        visitor_hash: visitor_hash,
        path: request.path.to_s.first(500),
        source_path: source_path.to_s.first(500),
        metadata: metadata,
        occurred_at: Time.current
      )
      marketing_campaign&.register_conversion! if conversion_event?
      event
    rescue => e
      Rails.logger.warn("[Seo::ConversionTracker] #{e.class}: #{e.message}")
      nil
    end

    private

    attr_reader :event_type, :request, :lead, :habitation, :metadata

    def seo_setting
      @seo_setting ||= canonical_path_candidates.filter_map do |path|
        SeoSetting.find_by(canonical_path: path)
      end.first
    end

    def marketing_campaign
      @marketing_campaign ||= begin
        campaign_from_params || campaign_from_utm || campaign_from_page
      end
    end

    def campaign_from_params
      campaign_id = safe_params[:marketing_campaign_id].presence || safe_params[:campaign_id].presence
      return if campaign_id.blank?

      MarketingCampaign.find_by(id: campaign_id)
    end

    def campaign_from_utm
      campaign_key = safe_params[:utm_campaign].presence || uri_query_params(source_path)["utm_campaign"].presence
      return if campaign_key.blank?

      MarketingCampaign.find_by(utm_campaign: campaign_key) || MarketingCampaign.find_by(slug: campaign_key)
    end

    def campaign_from_page
      return nil unless seo_setting

      MarketingCampaign.active_or_planned.where(seo_setting: seo_setting).order(priority: :asc, updated_at: :desc).first
    end

    def source_path
      @source_path ||= begin
        uri = URI.parse(request.referer.to_s)
        if uri.path.present?
          uri.query.present? ? "#{uri.path}?#{uri.query}" : uri.path
        else
          request.fullpath.presence || request.path
        end
      rescue
        request.fullpath.presence || request.path
      end
    end

    def canonical_path_candidates
      [
        source_path,
        without_tracking_params(source_path),
        request.fullpath.to_s,
        without_tracking_params(request.fullpath.to_s),
        request.path.to_s
      ].compact_blank.uniq
    end

    def without_tracking_params(path)
      uri = URI.parse(path)
      params = Rack::Utils.parse_nested_query(uri.query)
      params.reject! { |key, _value| key.to_s.start_with?("utm_") || %w[gclid fbclid msclkid].include?(key.to_s) }
      query = params.to_query
      query.present? ? "#{uri.path}?#{query}" : uri.path
    rescue
      nil
    end

    def safe_params
      request.respond_to?(:params) ? request.params.to_h : {}
    rescue
      {}
    end

    def uri_query_params(path)
      Rack::Utils.parse_nested_query(URI.parse(path.to_s).query)
    rescue
      {}
    end

    def conversion_event?
      %w[lead_created schedule_visit].include?(event_type.to_s)
    end

    def visitor_hash
      source = [
        request.remote_ip,
        request.user_agent,
        safe_session_id.presence || "no-session"
      ].join("|")

      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base.to_s, source)
    end

    def safe_session_id
      request.session.id&.public_id
    rescue
      nil
    end
  end
end
