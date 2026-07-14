module Dashboard
  class LeadAcquisitionQuery
    CHANNEL_LABELS = {
      "meta_ads" => "Meta Ads", "google_ads" => "Google Ads",
      "microsoft_ads" => "Microsoft Ads", "organic_search" => "Busca orgânica",
      "organic_social" => "Social orgânico", "referral" => "Referência",
      "campaign" => "Outras campanhas", "direct" => "Direto / desconhecido"
    }.freeze
    PAID_CHANNELS = %w[meta_ads google_ads microsoft_ads].freeze
    CAMPAIGN_ID_KEYS = %w[utm_id campaign_id gad_campaignid].freeze

    def initialize(scope:, starts_at:, tenant:)
      @scope = scope.where("leads.created_at >= ?", starts_at)
      @tenant = tenant
    end

    def call
      counts = @scope.group(:attribution_channel).count
      counts["direct"] = counts.fetch("direct", 0) + counts.delete(nil).to_i
      counts.delete("direct") if counts["direct"].zero?
      total = counts.values.sum
      unknown = counts.fetch("direct", 0)

      {
        total: total,
        attributed: total - unknown,
        unknown: unknown,
        attribution_rate: total.zero? ? 0 : (((total - unknown).to_f / total) * 100).round(1),
        channels: channel_rows(counts, total),
        trend: trend_rows,
        campaigns: campaign_rows
      }
    end

    private

    def channel_rows(counts, total)
      counts.map do |channel, count|
        { key: channel, label: CHANNEL_LABELS.fetch(channel, channel.to_s.humanize), count: count,
          percentage: total.zero? ? 0 : ((count.to_f / total) * 100).round(1) }
      end.sort_by { |row| -row[:count] }
    end

    def trend_rows
      raw = @scope.group("DATE(leads.created_at)", :attribution_channel).count
      raw.map { |(date, channel), count| { date: date.to_date.iso8601, channel: channel.presence || "direct", count: count } }
    end

    def campaign_rows
      local_names = @tenant.marketing_campaigns.where.not(utm_campaign: [nil, ""]).pluck(:utm_campaign, :name).to_h
      grouped = Hash.new { |hash, key| hash[key] = { count: 0 } }

      @scope.where(attribution_channel: PAID_CHANNELS).pluck(:attribution_channel, :attribution_data).each do |channel, raw_data|
        data = raw_data.to_h.stringify_keys
        utm_campaign = data["utm_campaign"].presence
        external_id = CAMPAIGN_ID_KEYS.filter_map { |key| data[key].presence }.first
        name = local_names[utm_campaign] || data["campaign_name"].presence || utm_campaign
        key = [channel, name, external_id]
        grouped[key][:count] += 1
      end

      grouped.map do |(channel, name, external_id), values|
        { channel: channel, channel_label: CHANNEL_LABELS.fetch(channel), name: name,
          external_id: external_id, count: values[:count] }
      end.sort_by { |row| -row[:count] }.first(8)
    end
  end
end
