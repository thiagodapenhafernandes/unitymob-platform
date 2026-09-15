module Dashboard
  class LeadAcquisitionQuery
    CHANNEL_LABELS = {
      "meta_ads" => "Meta Ads", "google_ads" => "Google Ads",
      "microsoft_ads" => "Microsoft Ads", "organic_search" => "Busca orgânica",
      "organic_social" => "Social orgânico", "referral" => "Referência",
      "campaign" => "Outras campanhas", "direct" => "Direto / desconhecido"
    }.merge(Leads::Attribution::CHANNEL_LABELS).freeze
    SOURCE_LABELS = Leads::Attribution::SOURCE_LABELS.merge(
      "direct" => "Direto / desconhecido",
      "unknown" => "Direto / desconhecido"
    ).freeze
    PAID_CHANNELS = (Leads::Attribution::PAID_SOURCES.values + ["paid_campaign"]).uniq.freeze
    CAMPAIGN_ID_KEYS = %w[utm_id campaign_id gad_campaignid].freeze

    def initialize(scope:, starts_at:, tenant:, ends_at: nil)
      @scope = scope.where("leads.created_at >= ?", starts_at)
      @scope = @scope.where("leads.created_at <= ?", ends_at) if ends_at
      @tenant = tenant
    end

    def call
      counts = normalized_channel_counts(source_group_counts)
      total = counts.values.sum
      unknown = counts.fetch("direct", 0)

      {
        total: total,
        attributed: total - unknown,
        unknown: unknown,
        attribution_rate: total.zero? ? 0 : (((total - unknown).to_f / total) * 100).round(1),
        channels: channel_rows(counts, total),
        trend: trend_rows,
        campaigns: campaign_rows,
        channel_quality: channel_quality_rows(counts)
      }
    end

    private

    def source_sql
      <<~SQL.squish
        COALESCE(
          NULLIF(TRIM(leads.origin), ''),
          NULLIF(TRIM(leads.attribution_data ->> 'label'), ''),
          NULLIF(TRIM(leads.attribution_source), ''),
          NULLIF(TRIM(leads.attribution_channel), ''),
          'direct'
        )
      SQL
    end

    def source_group_counts
      @scope.group(Arel.sql(source_sql)).count
    end

    def normalized_channel_counts(raw_counts)
      raw_counts.each_with_object(Hash.new(0)) do |(channel, count), grouped|
        grouped[normalized_channel(channel)] += count.to_i
      end.reject { |_channel, count| count.zero? }
    end

    def normalized_channel(channel)
      channel.to_s.presence || "direct"
    end

    def channel_rows(counts, total)
      counts.map do |channel, count|
        { key: channel, label: source_label(channel), count: count,
          percentage: total.zero? ? 0 : ((count.to_f / total) * 100).round(1),
          filter_params: source_filter_params(channel) }
      end.sort_by { |row| -row[:count] }
    end

    def trend_rows
      raw = @scope.group("DATE(leads.created_at)", Arel.sql(source_sql)).count
      raw.map { |(date, channel), count| { date: date.to_date.iso8601, channel: normalized_channel(channel), count: count } }
    end

    def campaign_rows
      local_names = @tenant.marketing_campaigns.where.not(utm_campaign: [nil, ""]).pluck(:utm_campaign, :name).to_h
      grouped = Hash.new { |hash, key| hash[key] = { count: 0, lead_ids: [] } }

      @scope.where(attribution_channel: PAID_CHANNELS).pluck(:id, :attribution_channel, :attribution_data).each do |lead_id, channel, raw_data|
        data = raw_data.to_h.stringify_keys
        utm_campaign = data["utm_campaign"].presence
        external_id = CAMPAIGN_ID_KEYS.filter_map { |key| data[key].presence }.first
        name = local_names[utm_campaign] || data["campaign_name"].presence || utm_campaign
        key = [channel, name, external_id]
        grouped[key][:count] += 1
        grouped[key][:lead_ids] << lead_id
      end

      grouped.map do |(channel, name, external_id), values|
        lead_ids = values[:lead_ids]
        visits = Appointment.where(kind: "visita", lead_id: lead_ids).distinct.count(:lead_id)
        proposals = Proposal.where.not(status: "rascunho").where(lead_id: lead_ids).distinct.count(:lead_id)
        closed = @scope.where(id: lead_ids, status: Lead.status_value(:concluido)).count
        opportunity = [visits, proposals, closed].max
        { channel: channel, channel_label: CHANNEL_LABELS.fetch(channel), name: name,
          external_id: external_id, count: values[:count], visits: visits, proposals: proposals, closed: closed,
          opportunity_rate: values[:count].zero? ? 0 : ((opportunity.to_f / values[:count]) * 100).round(1) }
      end.sort_by { |row| [-row[:opportunity_rate], -row[:count]] }.first(8)
    end

    def channel_quality_rows(counts)
      visits = outcome_counts(Appointment.where(kind: "visita"), "appointments.lead_id")
      proposals = outcome_counts(Proposal.where.not(status: "rascunho"), "proposals.lead_id")
      closed = normalized_channel_counts(@scope.where(status: Lead.status_value(:concluido)).group(Arel.sql(source_sql)).count)

      counts.map do |channel, total|
        visit_count = visits[channel].to_i
        proposal_count = proposals[channel].to_i
        closed_count = closed[channel].to_i
        opportunity_count = [visit_count, proposal_count, closed_count].max

        {
          key: channel,
          label: source_label(channel),
          total: total,
          visits: visit_count,
          proposals: proposal_count,
          closed: closed_count,
          filter_params: source_filter_params(channel),
          opportunity_rate: total.zero? ? 0 : ((opportunity_count.to_f / total) * 100).round(1)
        }
      end.sort_by { |row| [-row[:opportunity_rate], -row[:total]] }.first(6)
    end

    def outcome_counts(relation, counted_column)
      raw_counts = relation
        .joins(:lead)
        .merge(@scope)
        .group(Arel.sql(source_sql))
        .distinct
        .count(counted_column)
      normalized_channel_counts(raw_counts)
    end

    def source_filter_params(channel)
      { source_filter: channel }
    end

    def source_label(value)
      raw = value.to_s.strip
      normalized = raw.parameterize(separator: "_")
      return "Direto / desconhecido" if raw.blank? || normalized.in?(%w[direct unknown origem_nao_identificada direto_origem_desconhecida])
      return CHANNEL_LABELS[raw] if CHANNEL_LABELS.key?(raw)
      return SOURCE_LABELS[raw.downcase] if SOURCE_LABELS.key?(raw.downcase)
      return "Meta Ads" if normalized.match?(/meta_ads|facebook_lead_ads/)
      return "Facebook" if normalized.match?(/\Afacebook|\Afb\z/)
      return "Instagram" if normalized.match?(/instagram|\Aig\z/)
      return "WhatsApp" if normalized.include?("whatsapp")
      return "Site" if normalized.match?(/\Asite\z|formulario|whatsapp_modal|whatsapp_click/)
      return "Showroom" if normalized.match?(/showroom|vitrine/)
      return "Portal imobiliário" if normalized.match?(/zap|vivareal|olx|imovelweb|chaves_na_mao/)
      return "Integração externa" if normalized.match?(/webhook|integracao|external|c2s|migra/)

      raw.tr("_-", " ").squish.titleize
    end
  end
end
