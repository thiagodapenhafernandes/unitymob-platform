module Footer
  class QuickLinksService
    Link = Struct.new(:label, :url, keyword_init: true)

    LIMIT = 10
    CACHE_KEY = "footer_quick_links_v2"

    class << self
      def call(limit: LIMIT)
        # Inclui o tenant na chave: os candidatos de Habitation são escopados por
        # conta, então o cache não pode ser global sob pena de vazar entre tenants.
        Rails.cache.fetch("#{CACHE_KEY}:t#{Current.tenant&.id || 'public'}:#{limit}", expires_in: 30.minutes) do
          new(limit: limit).call
        end
      end

      def clear_cache
        return unless Rails.cache.respond_to?(:delete_matched)

        Rails.cache.delete_matched("#{CACHE_KEY}:*")
      rescue NotImplementedError
        nil
      end
    end

    def initialize(limit: LIMIT)
      @limit = limit
    end

    def call
      links = []
      append_links(links, most_accessed_links)
      append_links(links, property_link_candidates) if links.size < limit
      append_links(links, general_link_candidates) if links.size < limit
      append_links(links, development_link_candidates) if links.size < limit
      append_links(links, fallback_links) if links.size < limit
      links
    end

    private

    attr_reader :limit

    def most_accessed_links
      tenant = Current.tenant
      return [] if tenant.blank?

      tenant.seo_settings
        .where(active: true, apply_to_public: true, robots_index: true)
        .where("access_count > 0")
        .where(page_type: public_listing_page_types)
        .order(access_count: :desc, last_accessed_at: :desc, seo_score: :desc)
        .limit(limit * 3)
        .filter_map do |seo|
          path = seo.sanitized_canonical_path.presence
          next if path.blank?

          Link.new(label: label_for_seo(seo), url: path)
        end
    end

    def append_links(links, candidates)
      candidates.each do |link|
        next if links.any? { |existing| normalize_url(existing.url) == normalize_url(link.url) }

        links << link
        break if links.size >= limit
      end
    end

    def property_link_candidates
      Enumerator.new do |yielder|
        Seo::StrategicLanding.property_links.each do |link|
          next unless property_link_available?(link)

          yielder << Link.new(label: link[:label].to_s.titleize, url: link[:path])
        end
      end
    end

    def development_link_candidates
      Enumerator.new do |yielder|
        Seo::StrategicLanding.development_links.each do |link|
          next unless development_link_available?(link)

          yielder << Link.new(label: "Empreendimentos #{link[:label]}", url: link[:path])
        end
      end
    end

    def general_link_candidates
      Enumerator.new do |yielder|
        general_link_definitions.each do |link|
          next unless general_link_available?(link.url)

          yielder << link
        end
      end
    end

    def property_links
      Seo::StrategicLanding.property_links.filter_map do |link|
        next unless property_link_available?(link)

        Link.new(label: link[:label].to_s.titleize, url: link[:path])
      end
    end

    def development_links
      Seo::StrategicLanding.development_links.filter_map do |link|
        next unless development_link_available?(link)

        Link.new(label: "Empreendimentos #{link[:label]}", url: link[:path])
      end
    end

    def general_links
      general_link_definitions.select { |link| general_link_available?(link.url) }
    end

    def strategic_links
      property_links + general_links + development_links
    end

    def general_link_definitions
      [
        Link.new(label: "Imóveis para locação", url: "/aluguel"),
        Link.new(label: "Empreendimentos", url: "/empreendimentos"),
        Link.new(label: "Corporativos", url: "/corporativos")
      ]
    end

    def fallback_links
      [
        Link.new(label: "Home", url: "/"),
        Link.new(label: "Buscar Imóveis", url: "/imoveis"),
        Link.new(label: "Contato", url: "/contato")
      ]
    end

    def public_listing_page_types
      %w[
        property_listing
        property_landing
        developments_index
        development_landing
        pages_links_uteis
        pages_corporativos
        home_index
      ]
    end

    def label_for_seo(seo)
      strategic_label_for_path(seo.sanitized_canonical_path) ||
        clean_label(seo.display_name)
    end

    def strategic_label_for_path(path)
      property = Seo::StrategicLanding.property_links.find { |link| link[:path] == path }
      return property[:label].to_s.titleize if property

      development = Seo::StrategicLanding.development_links.find { |link| link[:path] == path }
      return "Empreendimentos #{development[:label]}" if development

      {
        "/" => "Home",
        "/imoveis" => "Buscar Imóveis",
        "/aluguel" => "Imóveis para locação",
        "/empreendimentos" => "Empreendimentos",
        "/corporativos" => "Corporativos",
        "/contato" => "Contato"
      }[path]
    end

    def clean_label(value)
      value
        .to_s
        .gsub(/\s*\|\s*Salute Imóveis.*/i, "")
        .gsub(/\s+/, " ")
        .strip
        .truncate(42)
    end

    # Escopa por conta quando há tenant resolvido (site público seta Current.tenant
    # via ApplicationController#set_current_public_tenant). Sem tenant, mantém o
    # comportamento anterior (global) explicitamente para não quebrar contextos
    # sem resolução de conta.
    def habitations
      Current.tenant&.habitations || Habitation.none
    end

    def property_link_available?(link)
      habitations.public_property_search(link[:params])
                 .exists?
    end

    def development_link_available?(link)
      habitations.empreendimentos_publicos
                 .advanced_search(link[:params])
                 .exists?
    rescue ActiveRecord::StatementInvalid
      habitations.empreendimentos_publicos.exists?
    end

    def general_link_available?(path)
      case path
      when "/aluguel"
        habitations.active.without_developments.for_rent.exists?
      when "/empreendimentos"
        habitations.empreendimentos_publicos.exists?
      when "/corporativos"
        habitations.active.without_developments.home_corporate.exists?
      else
        true
      end
    end

    def normalize_url(url)
      url.to_s.delete_suffix("/").presence || "/"
    end
  end
end
