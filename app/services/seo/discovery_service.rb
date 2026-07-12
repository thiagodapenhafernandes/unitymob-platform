require "cgi"

module Seo
  class DiscoveryService
    STATUS_PREFIX = "seo_discovery".freeze

    Result = Struct.new(:evaluated, :created, :updated, :indexable, :noindex, :ai_enqueued, :skipped, :errors, keyword_init: true)

    def self.status
      {
        status: Setting.get("#{STATUS_PREFIX}_status", "idle"),
        message: Setting.get("#{STATUS_PREFIX}_message", "Descoberta SEO ainda não executada."),
        evaluated: Setting.get("#{STATUS_PREFIX}_evaluated", "0").to_i,
        created: Setting.get("#{STATUS_PREFIX}_created", "0").to_i,
        updated: Setting.get("#{STATUS_PREFIX}_updated", "0").to_i,
        indexable: Setting.get("#{STATUS_PREFIX}_indexable", "0").to_i,
        noindex: Setting.get("#{STATUS_PREFIX}_noindex", "0").to_i,
        ai_enqueued: Setting.get("#{STATUS_PREFIX}_ai_enqueued", "0").to_i,
        skipped: Setting.get("#{STATUS_PREFIX}_skipped", "0").to_i,
        errors: Setting.get("#{STATUS_PREFIX}_errors", "0").to_i,
        last_run_at: parse_time(Setting.get("#{STATUS_PREFIX}_last_run_at")),
        last_error: Setting.get("#{STATUS_PREFIX}_last_error", "")
      }
    end

    def self.enabled?
      Setting.get("#{STATUS_PREFIX}_enabled", "1") == "1"
    end

    def self.save_enabled!(value)
      Setting.set("#{STATUS_PREFIX}_enabled", value ? "1" : "0", "Ativa descoberta SEO automática")
    end

    def self.parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def initialize(generate_ai: true)
      @generate_ai = generate_ai && Ai::SeoContentService.connected? && Seo::PageTracker.auto_ai?
      @result = Result.new(evaluated: 0, created: 0, updated: 0, indexable: 0, noindex: 0, ai_enqueued: 0, skipped: 0, errors: 0)
    end

    def call
      mark_status!("running", "Descobrindo oportunidades SEO...")
      opportunities.each { |opportunity| process(opportunity) }
      persist_result!("completed", "Descoberta SEO concluída.")
      @result
    rescue => e
      @result.errors += 1
      mark_status!("failed", "Falha na descoberta SEO: #{e.message}", last_error: e.message)
      raise
    end

    private

    def opportunities
      strategic_property_opportunities + strategic_development_opportunities + dynamic_property_opportunities + dynamic_development_opportunities
    end

    def strategic_property_opportunities
      Seo::StrategicLanding::PROPERTY_PAGES.map do |slug, data|
        build_opportunity(
          canonical_key: "properties_landing:#{slug}",
          page_name: "imoveis:#{slug}",
          page_type: "property_landing",
          canonical_path: "/imoveis/#{slug}",
          normalized_params: data[:params],
          title: data[:title],
          description: data[:description],
          keywords: [data[:label], "imóveis", "Balneário Camboriú", site_name].join(", "),
          intro_text: Seo::StrategicLanding.property_intro(data),
          count: count_properties(data[:params])
        )
      end
    end

    def strategic_development_opportunities
      Seo::StrategicLanding::DEVELOPMENT_PAGES.map do |slug, data|
        build_opportunity(
          canonical_key: "developments_landing:#{slug}",
          page_name: "empreendimentos:#{slug}",
          page_type: "development_landing",
          canonical_path: "/empreendimentos/#{slug}",
          normalized_params: data[:params],
          title: data[:title],
          description: data[:description],
          keywords: [data[:label], "empreendimentos", "Balneário Camboriú", site_name].join(", "),
          intro_text: Seo::StrategicLanding.development_intro(data),
          count: count_developments(data[:params])
        )
      end
    end

    def dynamic_property_opportunities
      opportunities = []
      top_values(:cidade, habitation_scope.active.without_developments, limit: 8).each do |city, _count|
        params = { city: [city] }
        opportunities << build_opportunity(
          canonical_key: "properties_discovery:city:#{city.to_s.parameterize}",
          page_name: "imoveis:city:#{city.to_s.parameterize}",
          page_type: "property_listing",
          canonical_path: "/imoveis?city=#{CGI.escape(city.to_s)}",
          normalized_params: params,
          title: "Imóveis em #{city}",
          description: "Imóveis em #{city} selecionados pela #{site_name} para compra, locação e investimento.",
          keywords: ["imóveis em #{city}", "imobiliária", site_name].join(", "),
          intro_text: "",
          count: count_properties(params)
        )
      end

      top_values(:bairro, habitation_scope.active.without_developments, limit: 10).each do |bairro, _count|
        params = { city: [bairro] }
        count = count_properties(params)
        next if count < 3

        opportunities << build_opportunity(
          canonical_key: "properties_discovery:neighborhood:#{bairro.to_s.parameterize}",
          page_name: "imoveis:neighborhood:#{bairro.to_s.parameterize}",
          page_type: "property_listing",
          canonical_path: "/imoveis?city=#{CGI.escape(bairro.to_s)}",
          normalized_params: params,
          title: "Imóveis em #{bairro}",
          description: "Imóveis em #{bairro} com curadoria da #{site_name} para quem busca localização e boas oportunidades.",
          keywords: ["imóveis em #{bairro}", "Balneário Camboriú", site_name].join(", "),
          intro_text: "",
          count: count
        )
      end

      opportunities
    end

    def dynamic_development_opportunities
      top_values(:cidade, habitation_scope.empreendimentos_publicos, limit: 8).map do |city, count|
        build_opportunity(
          canonical_key: "developments_discovery:city:#{city.to_s.parameterize}",
          page_name: "empreendimentos:city:#{city.to_s.parameterize}",
          page_type: "developments_index",
          canonical_path: "/empreendimentos?city=#{CGI.escape(city.to_s)}",
          normalized_params: { city: [city] },
          title: "Empreendimentos em #{city}",
          description: "Empreendimentos em #{city} para morar, investir ou acompanhar novos projetos imobiliários.",
          keywords: ["empreendimentos em #{city}", "lançamentos", site_name].join(", "),
          intro_text: "",
          count: count
        )
      end
    end

    def build_opportunity(attributes)
      indexable = attributes[:count].to_i.positive?
      attributes.merge(
        robots_index: indexable,
        robots_follow: true,
        active: true,
        apply_to_public: true,
        auto_discovered: true
      )
    end

    def site_name
      LayoutSetting.instance.site_name.presence || "Unitymob"
    rescue StandardError
      "Unitymob"
    end

    def process(opportunity)
      @result.evaluated += 1
      seo = seo_tenant.seo_settings.find_or_initialize_by(canonical_key: opportunity[:canonical_key])
      created = seo.new_record?

      if seo.persisted? && seo.manual_mode?
        @result.skipped += 1
        return
      end

      seo.assign_attributes(
        page_name: opportunity[:page_name],
        page_type: opportunity[:page_type],
        controller_name: inferred_controller(opportunity[:page_type]),
        action_name: "index",
        canonical_path: opportunity[:canonical_path],
        canonical_url: opportunity[:canonical_path],
        normalized_params: opportunity[:normalized_params],
        robots_index: opportunity[:robots_index],
        robots_follow: opportunity[:robots_follow],
        active: opportunity[:active],
        apply_to_public: opportunity[:apply_to_public],
        auto_discovered: true,
        meta_title: seo.meta_title.presence || opportunity[:title],
        meta_description: seo.meta_description.presence || opportunity[:description],
        meta_keywords: seo.meta_keywords.presence || opportunity[:keywords],
        intro_text: seo.intro_text.presence || opportunity[:intro_text],
        og_title: seo.og_title.presence || opportunity[:title],
        og_description: seo.og_description.presence || opportunity[:description],
        last_generated_from_path: "seo_discovery"
      )
      seo.save!

      @result.created += 1 if created
      @result.updated += 1 unless created
      opportunity[:robots_index] ? @result.indexable += 1 : @result.noindex += 1

      enqueue_ai(seo) if @generate_ai && should_generate_ai?(seo)
    rescue => e
      @result.errors += 1
      Rails.logger.warn("[Seo::DiscoveryService] #{opportunity[:canonical_key]} #{e.class}: #{e.message}")
    end

    def should_generate_ai?(seo)
      seo.robots_index? && !seo.manual_mode? && seo.ai_status.in?(%w[pending failed skipped])
    end

    def enqueue_ai(seo)
      SeoAiGenerationJob.perform_later(seo.id, tenant_id: seo_tenant.id)
      seo.update_columns(ai_status: "pending")
      @result.ai_enqueued += 1
    end

    def inferred_controller(page_type)
      page_type.to_s.include?("development") ? "empreendimentos" : "habitations"
    end

    def count_properties(params)
      habitation_scope.public_property_search(params).count
    end

    def count_developments(params)
      scope = habitation_scope.empreendimentos_publicos.left_outer_joins(:address)
      scope = apply_location(scope, Array(params[:city]))
      Array(params[:characteristics]).reduce(scope) do |current_scope, characteristic|
        current_scope.respond_to?(characteristic) ? current_scope.public_send(characteristic) : current_scope
      end.count
    end

    # Nunca agrega imóveis cross-tenant: usa o tenant do contexto (job/admin)
    # com fallback no tenant do site público (console/execuções sem contexto).
    def habitation_scope
      seo_tenant.habitations
    end

    def seo_tenant
      @seo_tenant ||= Current.tenant || Tenant.public_for
    end

    def apply_location(scope, locations)
      locations.reject(&:blank?).reduce(scope) do |current_scope, location|
        bairro, cidade = location.to_s.split(" - ", 2).map(&:strip)
        if bairro.present? && cidade.present?
          current_scope.where(
            "unaccent(COALESCE(addresses.bairro, habitations.bairro)) ILIKE unaccent(?) AND unaccent(COALESCE(addresses.cidade, habitations.cidade)) ILIKE unaccent(?)",
            bairro,
            cidade
          )
        else
          current_scope.where(
            "unaccent(COALESCE(addresses.cidade, habitations.cidade, addresses.bairro, habitations.bairro)) ILIKE unaccent(?)",
            location
          )
        end
      end
    end

    def top_values(field, scope, limit:)
      field_sql = field == :cidade ? "COALESCE(addresses.cidade, habitations.cidade)" : "COALESCE(addresses.bairro, habitations.bairro)"
      scope.left_outer_joins(:address)
           .where("#{field_sql} IS NOT NULL")
           .group(Arel.sql(field_sql))
           .order(Arel.sql("COUNT(*) DESC"))
           .limit(limit)
           .count
           .reject { |value, _| value.blank? }
    end

    def mark_status!(status, message, last_error: nil)
      Setting.set("#{STATUS_PREFIX}_status", status, "Status da descoberta SEO")
      Setting.set("#{STATUS_PREFIX}_message", message, "Mensagem da descoberta SEO")
      Setting.set("#{STATUS_PREFIX}_last_error", last_error.to_s, "Último erro da descoberta SEO") if last_error
    end

    def persist_result!(status, message)
      mark_status!(status, message, last_error: "")
      {
        evaluated: @result.evaluated,
        created: @result.created,
        updated: @result.updated,
        indexable: @result.indexable,
        noindex: @result.noindex,
        ai_enqueued: @result.ai_enqueued,
        skipped: @result.skipped,
        errors: @result.errors
      }.each do |key, value|
        Setting.set("#{STATUS_PREFIX}_#{key}", value.to_s, "Métrica da descoberta SEO")
      end
      Setting.set("#{STATUS_PREFIX}_last_run_at", Time.current.iso8601, "Última execução da descoberta SEO")
    end
  end
end
