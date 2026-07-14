module Leads
  class Attribution
    TRACKING_KEYS = %w[
      landing_url referrer_url utm_source utm_medium utm_campaign utm_term
      utm_content utm_id campaign_id gad_campaignid gclid fbclid msclkid gbraid wbraid
    ].freeze
    PAID_MEDIA = %w[cpc ppc paid paid_social paidsearch display retargeting].freeze

    Result = Data.define(:channel, :source, :label, :data)

    def self.apply!(lead, raw:, request: nil)
      result = new(raw: raw, request: request).result
      return lead if result.data.empty?

      lead.attribution_channel = result.channel
      lead.attribution_source = result.source
      lead.attribution_data = lead.attribution_data.to_h.merge(result.data)
      lead.origin = result.label if lead.origin.blank?
      lead
    end

    def initialize(raw:, request: nil)
      @raw = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : {}.with_indifferent_access
      @request = request
    end

    def result
      @result ||= begin
        data = sanitized_data
        channel, source, label = classify(data)
        Result.new(channel: channel, source: source, label: label, data: data)
      end
    end

    private

    def sanitized_data
      TRACKING_KEYS.each_with_object({}) do |key, payload|
        value = @raw[key].to_s.strip
        next if value.blank?

        payload[key] = url_key?(key) ? safe_url(value) : value.first(1024)
      end.compact.merge("captured_at" => Time.current.iso8601)
    end

    def safe_url(value)
      uri = URI.parse(value.first(4096))
      return unless uri.is_a?(URI::HTTP) && uri.host.present?

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def url_key?(key)
      key.end_with?("_url")
    end

    def classify(data)
      source = data["utm_source"].to_s.downcase
      medium = data["utm_medium"].to_s.downcase
      referrer_host = host_for(data["referrer_url"])
      paid = PAID_MEDIA.include?(medium) || medium.include?("paid")

      return ["google_ads", "google", "Google Ads"] if data["gclid"].present? || (source.include?("google") && paid)
      return ["meta_ads", "meta", "Meta Ads"] if data["fbclid"].present? || (%w[meta facebook instagram].any? { |item| source.include?(item) } && paid)
      return ["microsoft_ads", "microsoft", "Microsoft Ads"] if data["msclkid"].present? || (%w[bing microsoft].any? { |item| source.include?(item) } && paid)

      return ["campaign", source, campaign_label(source)] if source.present?
      return ["organic_search", "google", "Google orgânico"] if google_host?(referrer_host)
      return ["organic_search", "bing", "Bing orgânico"] if referrer_host.end_with?("bing.com")
      return ["organic_social", "instagram", "Instagram / social"] if social_host?(referrer_host)
      return ["referral", referrer_host, "Referência: #{referrer_host}"] if external_referrer?(referrer_host)

      ["direct", "direct", "Direto / origem desconhecida"]
    end

    def campaign_label(source)
      source.tr("_-", " ").squish.presence&.titleize || "Campanha"
    end

    def host_for(value)
      URI.parse(value.to_s).host.to_s.downcase.sub(/\Awww\./, "")
    rescue URI::InvalidURIError
      ""
    end

    def google_host?(host)
      host == "google.com" || host.start_with?("google.") || host.include?(".google.")
    end

    def social_host?(host)
      %w[instagram.com facebook.com l.facebook.com lm.facebook.com linkme.bio].any? do |domain|
        host == domain || host.end_with?(".#{domain}")
      end
    end

    def external_referrer?(host)
      host.present? && host != @request&.host.to_s.downcase.sub(/\Awww\./, "")
    end
  end
end
