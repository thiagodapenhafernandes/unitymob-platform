module Leads
  class Attribution
    TRACKING_KEYS = %w[
      landing_url referrer_url utm_source utm_medium utm_campaign utm_term
      utm_content utm_id campaign_id campaign_name ad_id adset_id form_id
      gad_campaignid gclid fbclid msclkid gbraid wbraid ttclid
    ].freeze
    PAID_MEDIA = %w[cpc ppc paid paid_social paid-social paidsearch paid_search paid-social-media display retargeting cpm cpv].freeze
    SOURCE_ALIASES = {
      "google" => "google", "googleads" => "google", "google_ads" => "google",
      "bing" => "microsoft", "microsoft" => "microsoft", "microsoft_ads" => "microsoft",
      "facebook" => "facebook", "fb" => "facebook", "instagram" => "instagram", "ig" => "instagram", "meta" => "meta",
      "tiktok" => "tiktok", "tik_tok" => "tiktok", "linkedin" => "linkedin",
      "pinterest" => "pinterest", "twitter" => "x", "x" => "x", "youtube" => "youtube",
      "whatsapp" => "whatsapp", "telegram" => "telegram"
    }.freeze
    SOURCE_LABELS = {
      "google" => "Google", "microsoft" => "Bing", "facebook" => "Facebook", "instagram" => "Instagram",
      "meta" => "Meta", "tiktok" => "TikTok", "linkedin" => "LinkedIn", "pinterest" => "Pinterest",
      "x" => "X", "youtube" => "YouTube", "whatsapp" => "WhatsApp", "telegram" => "Telegram",
      "yahoo" => "Yahoo", "duckduckgo" => "DuckDuckGo", "baidu" => "Baidu", "yandex" => "Yandex"
    }.freeze
    PAID_SOURCES = {
      "google" => "google_ads", "microsoft" => "microsoft_ads", "meta" => "meta_ads",
      "facebook" => "meta_ads", "instagram" => "meta_ads", "tiktok" => "tiktok_ads",
      "linkedin" => "linkedin_ads", "pinterest" => "pinterest_ads", "x" => "x_ads", "youtube" => "youtube_ads"
    }.freeze
    CHANNEL_LABELS = {
      "google_ads" => "Google Ads", "microsoft_ads" => "Microsoft Ads", "meta_ads" => "Meta Ads",
      "tiktok_ads" => "TikTok Ads", "linkedin_ads" => "LinkedIn Ads", "pinterest_ads" => "Pinterest Ads",
      "x_ads" => "X Ads", "youtube_ads" => "YouTube Ads", "paid_campaign" => "Outras campanhas pagas",
      "email" => "E-mail", "messaging" => "Mensagens", "social" => "Social / mídia não identificada"
    }.freeze
    SEARCH_DOMAINS = {
      "google" => %w[google.com google.com.br google.pt google.co.uk google.es google.fr google.de google.it google.ca google.com.au google.co.jp google.com.ar],
      "microsoft" => %w[bing.com], "yahoo" => %w[search.yahoo.com], "duckduckgo" => %w[duckduckgo.com],
      "baidu" => %w[baidu.com], "yandex" => %w[yandex.com yandex.ru]
    }.freeze
    SOCIAL_DOMAINS = {
      "facebook" => %w[facebook.com fb.com], "instagram" => %w[instagram.com], "tiktok" => %w[tiktok.com],
      "linkedin" => %w[linkedin.com lnkd.in], "pinterest" => %w[pinterest.com pinterest.com.br pin.it],
      "x" => %w[x.com twitter.com t.co], "youtube" => %w[youtube.com youtu.be],
      "whatsapp" => %w[whatsapp.com wa.me], "telegram" => %w[telegram.org t.me]
    }.freeze
    Result = Data.define(:channel, :source, :label, :data)

    def self.apply!(lead, raw:, request: nil)
      raw = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : {}
      current = raw[:conversion_touch].is_a?(Hash) ? raw[:conversion_touch] : raw
      result = new(raw: current, request: request).result
      return lead if result.data.empty?

      first = new(raw: raw[:first_touch], request: request).result if raw[:first_touch].is_a?(Hash)
      lead.attribution_channel = result.channel
      lead.attribution_source = result.source
      lead.attribution_data = lead.attribution_data.to_h.merge(result.data).merge(
        "version" => 2, "model" => "conversion_session", "conversion_touch" => result.data
      )
      lead.attribution_data["first_touch"] = first.data if first && first.data.present?
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
        channel, source, label, evidence, confidence = classify(data)
        data = data.merge("channel" => channel, "source" => source, "label" => label,
          "evidence" => evidence, "confidence" => confidence, "captured_at" => Time.current.iso8601) if data.present?
        Result.new(channel: channel, source: source, label: label, data: data)
      end
    end

    private

    def sanitized_data
      TRACKING_KEYS.each_with_object({}) do |key, payload|
        raw = @raw[key]
        next unless raw.is_a?(String) || raw.is_a?(Numeric)
        value = raw.to_s.strip
        next if value.blank?
        payload[key] = key.end_with?("_url") ? safe_url(value) : value.first(1024)
      end.compact
    end

    def safe_url(value)
      uri = URI.parse(value.first(4096))
      return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def classify(data)
      clicks = { "google" => %w[gclid gbraid wbraid], "microsoft" => %w[msclkid], "tiktok" => %w[ttclid] }
        .filter_map { |source, keys| [source, keys.find { |key| data[key].present? }] if keys.any? { |key| data[key].present? } }
      return ["direct", "unknown", "Origem não identificada", "conflicting_click_ids", "unknown"] if clicks.size > 1
      if clicks.one?
        source, key = clicks.first
        return paid_result(source, "click_id:#{key}")
      end

      raw_source = data["utm_source"].to_s.downcase.strip
      source = SOURCE_ALIASES.fetch(raw_source, raw_source)
      medium = data["utm_medium"].to_s.downcase.strip
      return paid_result("unknown", "utm_medium") if source.blank? && PAID_MEDIA.include?(medium)
      if source.present?
        return paid_result(source, "utm_source+utm_medium") if PAID_MEDIA.include?(medium)
        channel = if %w[email e-mail newsletter].include?(medium)
          "email"
        elsif %w[whatsapp telegram].include?(source) || %w[messaging sms].include?(medium)
          "messaging"
        elsif %w[organic organic_search].include?(medium) && SEARCH_DOMAINS.key?(source)
          "organic_search"
        elsif %w[organic organic_social social social-network social_network].include?(medium) && SOCIAL_DOMAINS.key?(source)
          "organic_social"
        else
          "campaign"
        end
        return [channel, source, source_label(source), "utm_source+utm_medium", "declared"]
      end
      return ["social", "meta", "Meta", "click_id:fbclid", "inferred"] if data["fbclid"].present?
      host = host_for(data["referrer_url"])
      if external_referrer?(host)
        search = source_for_host(host, SEARCH_DOMAINS)
        return ["organic_search", search, "#{source_label(search)} orgânico", "referrer:#{host}", "inferred"] if search
        social = source_for_host(host, SOCIAL_DOMAINS)
        if social
          channel = %w[whatsapp telegram].include?(social) ? "messaging" : "social"
          return [channel, social, source_label(social), "referrer:#{host}", "inferred"]
        end
        return ["referral", host, "Referência: #{host}", "referrer:#{host}", "inferred"]
      end
      ["direct", "direct", "Direto / origem desconhecida", "no_external_signal", "unknown"]
    end

    def paid_result(source, evidence)
      channel = PAID_SOURCES.fetch(source, "paid_campaign")
      [channel, source, CHANNEL_LABELS.fetch(channel), evidence, "declared"]
    end

    def source_label(source)
      SOURCE_LABELS.fetch(source) { source.tr("_-", " ").squish.titleize }
    end

    def host_for(value)
      URI.parse(value.to_s).host.to_s.downcase.delete_suffix(".").delete_prefix("www.")
    rescue URI::InvalidURIError
      ""
    end

    def source_for_host(host, catalog)
      catalog.find { |_source, domains| domains.any? { |domain| host == domain || host.end_with?(".#{domain}") } }&.first
    end

    def external_referrer?(host)
      own_host = @request&.host.to_s.downcase.delete_prefix("www.")
      host.present? && host != own_host
    end
  end
end
