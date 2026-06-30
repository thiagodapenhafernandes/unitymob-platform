module Seo
  class MarketingInsights
    PropertyInsight = Struct.new(:habitation, :score, :reasons, :lead_count, :page_views, keyword_init: true)
    Alert = Struct.new(:level, :title, :description, :action_label, :action_path, keyword_init: true)

    STRATEGIC_PATHS = [
      "/imoveis/frente-mar",
      "/imoveis/quadra-mar",
      "/imoveis/praia-brava",
      "/imoveis/barra-sul",
      "/imoveis/lancamentos",
      "/empreendimentos",
      "/corporativos",
      "/aluguel"
    ].freeze

    def initialize(tenant: nil)
      @tenant = tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para insights de marketing" if @tenant.blank?
    end

    def call
      {
        campaign_opportunities: Seo::DashboardMetrics.new(period: "90").call[:campaign_opportunities],
        property_insights: property_insights,
        alerts: alerts,
        strategic_pages: strategic_pages,
        campaign_metrics: campaign_metrics
      }
    end

    def property_insights(limit: 20)
      lead_counts = tenant.leads.where.not(property_id: nil).group(:property_id).count
      page_view_counts = SeoConversionEvent.where(event_type: %w[property_card_click whatsapp_click lead_created schedule_visit])
                                         .where.not(habitation_id: nil)
                                         .where(habitation_id: tenant.habitations.select(:id))
                                         .group(:habitation_id)
                                         .count

      tenant.habitations.active
            .without_developments
            .with_attached_photos
            .newest_first
            .limit(120)
            .filter_map do |habitation|
        insight_for_property(habitation, lead_counts[habitation.id].to_i, page_view_counts[habitation.id].to_i)
      end.sort_by { |item| -item.score }.first(limit)
    end

    def alerts
      [
        alert_for_active_campaigns_without_conversion,
        alert_for_public_pages_without_recent_access,
        alert_for_weak_strategic_pages,
        alert_for_public_properties_without_images,
        alert_for_footer_links_without_stock
      ].compact
    end

    def strategic_pages
      STRATEGIC_PATHS.map do |path|
        seo = SeoSetting.find_by(canonical_path: path)
        {
          path: path,
          seo: seo,
          access_count: seo&.access_count.to_i,
          unique_visitors: seo&.page_visits&.distinct&.count(:visitor_hash).to_i,
          score: seo&.seo_score.to_i,
          stock: stock_for_path(path)
        }
      end
    end

    def campaign_metrics
      MarketingCampaign.includes(:seo_setting).recent.limit(20).map do |campaign|
        {
          campaign: campaign,
          clicks: campaign.clicks_count.to_i,
          conversions: campaign.conversions_count.to_i,
          conversion_rate: campaign.conversion_rate,
          cost_per_conversion: campaign.cost_per_conversion
        }
      end
    end

    private

    attr_reader :tenant

    def insight_for_property(habitation, lead_count, page_views)
      score = 0
      reasons = []

      if page_views.positive?
        score += [page_views * 5, 60].min
        reasons << "#{page_views} interações"
      end

      if lead_count.zero?
        score += 25
        reasons << "sem lead registrado"
      else
        score += [lead_count * 3, 30].min
        reasons << "#{lead_count} leads"
      end

      if habitation.primary_image_url.blank?
        score += 35
        reasons << "sem imagem principal"
      end

      if premium_property?(habitation)
        score += 25
        reasons << "ticket alto"
      end

      if strategic_property?(habitation)
        score += 25
        reasons << "perfil estratégico"
      end

      return nil if score <= 0

      PropertyInsight.new(habitation: habitation, score: score, reasons: reasons.uniq.first(4), lead_count: lead_count, page_views: page_views)
    end

    def premium_property?(habitation)
      price = habitation.valor_venda_cents.to_i
      price >= 2_000_000_00
    end

    def strategic_property?(habitation)
      text = [
        habitation.titulo_anuncio,
        habitation.bairro,
        habitation.cidade,
        habitation.caracteristicas,
        habitation.infra_estrutura
      ].join(" ").downcase

      text.match?(/frente mar|quadra mar|praia brava|barra sul|vista mar|lançamento|lancamento/)
    end

    def alert_for_active_campaigns_without_conversion
      count = MarketingCampaign.where(status: "active").where("clicks_count > 0 AND conversions_count = 0").count
      return if count.zero?

      Alert.new(
        level: "warning",
        title: "#{count} campanhas ativas sem conversão",
        description: "Há campanhas recebendo clique sem gerar lead ou agendamento.",
        action_label: "Ver campanhas",
        action_path: Rails.application.routes.url_helpers.admin_marketing_campaigns_path(status: "active")
      )
    end

    def alert_for_public_pages_without_recent_access
      count = SeoSetting.where(active: true, apply_to_public: true, robots_index: true)
                        .where("last_accessed_at IS NULL OR last_accessed_at < ?", 30.days.ago)
                        .count
      return if count.zero?

      Alert.new(
        level: "info",
        title: "#{count} páginas públicas sem acesso recente",
        description: "Boas candidatas para links internos, footer ou campanhas orgânicas.",
        action_label: "Ver páginas SEO",
        action_path: Rails.application.routes.url_helpers.admin_seo_settings_path
      )
    end

    def alert_for_weak_strategic_pages
      count = SeoSetting.where(canonical_path: STRATEGIC_PATHS).where("seo_score < 70").count
      return if count.zero?

      Alert.new(
        level: "danger",
        title: "#{count} páginas estratégicas com SEO fraco",
        description: "Páginas como frente mar, quadra mar e empreendimentos precisam estar fortes antes de mídia paga.",
        action_label: "Corrigir SEO",
        action_path: Rails.application.routes.url_helpers.admin_seo_settings_path
      )
    end

    def alert_for_public_properties_without_images
      count = tenant.habitations.active.without_developments.where.missing(:photos_attachments).limit(50).count
      return if count.zero?

      Alert.new(
        level: "danger",
        title: "#{count} imóveis públicos sem foto anexada",
        description: "Imóvel sem imagem derruba clique, confiança e conversão.",
        action_label: "Ver imóveis",
        action_path: Rails.application.routes.url_helpers.admin_habitations_path
      )
    end

    def alert_for_footer_links_without_stock
      links_without_stock = Footer::QuickLinksService.call.select { |link| stock_for_path(link.url).zero? }
      return if links_without_stock.blank?

      Alert.new(
        level: "warning",
        title: "#{links_without_stock.count} links rápidos sem estoque aparente",
        description: links_without_stock.map(&:label).join(", "),
        action_label: "Editar rodapé",
        action_path: Rails.application.routes.url_helpers.edit_admin_footer_setting_path
      )
    end

    def stock_for_path(path)
      case path
      when %r{\A/imoveis/frente-mar}
        tenant.habitations.active.without_developments.frente_mar.count
      when %r{\A/imoveis/quadra-mar}
        tenant.habitations.active.without_developments.quadra_mar.count
      when %r{\A/imoveis/praia-brava}
        tenant.habitations.active.without_developments.by_neighborhood("Praia Brava").count
      when %r{\A/imoveis/barra-sul}
        tenant.habitations.active.without_developments.by_neighborhood("Barra Sul").count
      when %r{\A/imoveis/lancamentos}
        tenant.habitations.active.without_developments.lancamento.count
      when %r{\A/empreendimentos}
        tenant.habitations.empreendimentos_publicos.count
      when %r{\A/corporativos}
        tenant.habitations.active.without_developments.home_corporate.count
      when %r{\A/aluguel}
        tenant.habitations.active.without_developments.for_rent.count
      else
        1
      end
    rescue
      0
    end
  end
end
