module Seo
  class DashboardMetrics
    CampaignOpportunity = Struct.new(:seo, :score, :reasons, :action_label, keyword_init: true)

    LISTING_TYPES = %w[property_listing property_landing developments_index development_landing pages_corporativos].freeze
    STRATEGIC_TERMS = {
      "frente mar" => 30,
      "quadra mar" => 24,
      "lançamento" => 22,
      "lancamento" => 22,
      "praia brava" => 22,
      "barra sul" => 20,
      "centro" => 14,
      "empreendimento" => 18,
      "corporativo" => 18,
      "locação" => 16,
      "locacao" => 16,
      "aluguel" => 16
    }.freeze

    attr_reader :period, :tenant

    def initialize(period: "30", tenant: Current.tenant)
      @tenant = tenant || raise(ArgumentError, "Tenant obrigatório para métricas SEO")
      @period = period.to_s.presence_in(%w[7 30 90 all]) || "30"
    end

    def call
      {
        period: period,
        summary: summary,
        daily_trend: daily_trend,
        score_buckets: score_buckets,
        page_type_counts: page_type_counts,
        top_pages: top_pages,
        campaign_opportunities: campaign_opportunities,
        active_campaigns: active_campaigns,
        recent_conversions: recent_conversions,
        seo_issues: seo_issues,
        recent_pages: recent_pages
      }
    end

    private

    def public_scope
      tenant.seo_settings.where(active: true, apply_to_public: true, robots_index: true)
    end

    def period_range
      return nil if period == "all"

      period.to_i.days.ago.to_date..Date.current
    end

    def trend_range
      days = period == "all" ? 30 : period.to_i
      (days - 1).days.ago.to_date..Date.current
    end

    def page_visits_scope
      scope = SeoPageVisit.where(seo_setting_id: tenant.seo_settings.select(:id))
      period_range ? scope.where(visited_on: period_range) : scope
    end

    def conversions_scope
      scope = SeoConversionEvent.where(seo_setting_id: tenant.seo_settings.select(:id))
      period_range ? scope.where(occurred_at: period_range.begin.beginning_of_day..Time.current) : scope
    end

    def summary
      scope = tenant.seo_settings
      {
        total_pages: scope.count,
        public_pages: public_scope.count,
        total_accesses: scope.sum(:access_count),
        unique_visitors: page_visits_scope.reorder(nil).distinct.count(:visitor_hash),
        period_visits: page_visits_scope.sum(:visits_count),
        period_unique_visitors: page_visits_scope.distinct.count(:visitor_hash),
        period_page_visits: page_visits_scope.count,
        period_conversions: conversions_scope.count,
        active_campaigns: tenant.marketing_campaigns.where(status: "active").count,
        accessed_pages: scope.where("access_count > 0").count,
        noindex_pages: scope.where(robots_index: false).count,
        weak_pages: scope.where("seo_score < 60").count,
        ai_generated_pages: scope.where(ai_status: "generated").count,
        last_accessed_at: scope.maximum(:last_accessed_at)
      }
    end

    def daily_trend
      visits_by_day = page_visits_scope
        .where(visited_on: trend_range)
        .group(:visited_on)
        .sum(:visits_count)

      unique_by_day = page_visits_scope
        .where(visited_on: trend_range)
        .group(:visited_on)
        .distinct
        .count(:visitor_hash)

      trend_range.map do |date|
        {
          date: date,
          visits: visits_by_day[date].to_i,
          unique_visitors: unique_by_day[date].to_i
        }
      end
    end

    def score_buckets
      {
        strong: tenant.seo_settings.where("seo_score >= 80").count,
        attention: tenant.seo_settings.where(seo_score: 60...80).count,
        weak: tenant.seo_settings.where("seo_score < 60").count
      }
    end

    def page_type_counts
      tenant.seo_settings.group(:page_type).count.sort_by { |_type, count| -count }.first(8)
    end

    def top_pages
      public_scope
        .joins(page_visits_join_sql)
        .select(
          "seo_settings.*",
          "COUNT(DISTINCT seo_page_visits.visitor_hash) AS unique_visitors_count",
          "COALESCE(SUM(seo_page_visits.visits_count), 0) AS period_visits_count"
        )
        .group("seo_settings.id")
        .having("COALESCE(SUM(seo_page_visits.visits_count), 0) > 0 OR seo_settings.access_count > 0")
        .order(Arel.sql("COUNT(DISTINCT seo_page_visits.visitor_hash) DESC"), Arel.sql("COALESCE(SUM(seo_page_visits.visits_count), 0) DESC"), access_count: :desc)
        .limit(10)
    end

    def page_visits_join_sql
      return "LEFT JOIN seo_page_visits ON seo_page_visits.seo_setting_id = seo_settings.id" unless period_range

      SeoSetting.sanitize_sql_array([
        "LEFT JOIN seo_page_visits ON seo_page_visits.seo_setting_id = seo_settings.id AND seo_page_visits.visited_on BETWEEN ? AND ?",
        period_range.begin,
        period_range.end
      ])
    end

    def campaign_opportunities
      candidates = public_scope
        .where(page_type: LISTING_TYPES)
        .where("access_count > 0 OR seo_score >= 65")
        .order(access_count: :desc, seo_score: :desc)
        .limit(80)

      candidates.filter_map do |seo|
        opportunity_for(seo)
      end.sort_by { |item| -item.score }.first(10)
    end

    def seo_issues
      public_scope
        .where("access_count > 0")
        .where("seo_score < 70 OR meta_description IS NULL OR meta_description = '' OR meta_title IS NULL OR meta_title = ''")
        .order(access_count: :desc, seo_score: :asc)
        .limit(10)
    end

    def recent_pages
      public_scope
        .where.not(last_accessed_at: nil)
        .order(last_accessed_at: :desc)
        .limit(10)
    end

    def active_campaigns
      tenant.marketing_campaigns
        .includes(:seo_setting)
        .where(status: %w[active planned])
        .order(priority: :asc, updated_at: :desc)
        .limit(8)
    end

    def recent_conversions
      conversions_scope
        .includes(:seo_setting, :marketing_campaign, :lead, :habitation)
        .then { |scope| period_range ? scope.where(occurred_at: period_range.begin.beginning_of_day..Time.current) : scope }
        .recent
        .limit(10)
    end

    def opportunity_for(seo)
      score = 0
      reasons = []

      if seo.access_count.to_i.positive?
        score += [seo.access_count.to_i, 100].min
        reasons << "#{seo.access_count} acessos"
      end

      unique_count = unique_visitors_for(seo)
      if unique_count.positive?
        score += [unique_count * 3, 60].min
        reasons << "#{unique_count} únicos"
      end

      if seo.seo_score.to_i >= 75
        score += 20
        reasons << "SEO pronto"
      elsif seo.seo_score.to_i.between?(60, 74)
        score += 10
        reasons << "SEO ajustável"
      end

      strategic_score, strategic_reason = strategic_signal(seo)
      score += strategic_score
      reasons << strategic_reason if strategic_reason.present?

      if stock_available?(seo)
        score += 25
        reasons << "tem estoque"
      else
        score -= 40
        reasons << "validar estoque"
      end

      return nil if score <= 0

      CampaignOpportunity.new(
        seo: seo,
        score: score,
        reasons: reasons.uniq.first(4),
        action_label: action_label_for(seo)
      )
    end

    def strategic_signal(seo)
      text = [
        seo.display_name,
        seo.meta_title,
        seo.meta_description,
        seo.meta_keywords,
        seo.sanitized_canonical_path
      ].compact.join(" ").downcase

      match = STRATEGIC_TERMS.find { |term, _score| text.include?(term) }
      match ? [match.last, match.first] : [0, nil]
    end

    def unique_visitors_for(seo)
      scope = seo.page_visits
      scope = scope.where(visited_on: period_range) if period_range
      scope.distinct.count(:visitor_hash)
    rescue
      0
    end

    def stock_available?(seo)
      path = seo.sanitized_canonical_path.to_s

      if path.start_with?("/empreendimentos")
        Habitation.empreendimentos_publicos.exists?
      elsif path == "/corporativos"
        Habitation.active.without_developments.home_corporate.exists?
      else
        Habitation.active.without_developments.exists?
      end
    rescue
      true
    end

    def action_label_for(seo)
      if seo.sanitized_canonical_path.to_s.start_with?("/empreendimentos")
        "Campanha de empreendimento"
      elsif seo.sanitized_canonical_path == "/corporativos"
        "Campanha corporativa"
      else
        "Campanha de imóveis"
      end
    end
  end
end
