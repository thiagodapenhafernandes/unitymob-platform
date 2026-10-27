module Leads
  class TrackingUid
    def self.capture(raw:, request: nil)
      raw = raw.to_h.with_indifferent_access
      candidates = [request&.cookies&.[]("user_id_mh"), raw[:utm_content],
        request&.query_parameters&.[]("utm_content")]
      page = raw[:landing_url].presence || raw[:page_url].presence || request&.referer
      candidates << Rack::Utils.parse_query(URI.parse(page.to_s).query.to_s)["utm_content"]
      candidates.find { |value| value.is_a?(String) && value.present? }
    rescue URI::InvalidURIError, ArgumentError
      candidates.find { |value| value.is_a?(String) && value.present? }
    end

    def self.merge(data, incoming)
      data = data.to_h.deep_dup
      uid = incoming.to_h["tracking_uid"]
      return data unless uid.is_a?(String) && uid.present?

      data["tracking_uid"] = uid if data["tracking_uid"].blank?
      data["tracking_uids"] = (Array(data["tracking_uids"]) + [data["tracking_uid"], uid] + Array(incoming["tracking_uids"])).uniq
      data
    end

    def self.payload(data)
      uid = data.to_h["tracking_uid"]
      uid.is_a?(String) && uid.present? ? { utm_content: uid, source: { utm: { utm_content: uid } } } : {}
    end
  end
end
