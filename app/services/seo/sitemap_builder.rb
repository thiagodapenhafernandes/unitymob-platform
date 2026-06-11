require "builder"
require "set"
require "uri"

module Seo
  class SitemapBuilder
    LIMIT = 45_000

    def initialize(base_url:, url_helpers:)
      @base_url = base_url.to_s.delete_suffix("/")
      @url_helpers = url_helpers
      @seen = Set.new
    end

    def to_xml
      xml = Builder::XmlMarkup.new(indent: 2)
      xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
      xml.urlset(
        "xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9",
        "xmlns:xhtml" => "http://www.w3.org/1999/xhtml"
      ) do
        sitemap_entries.first(LIMIT).each do |entry|
          xml.url do
            xml.loc entry[:loc]
            xml.lastmod entry[:lastmod].iso8601 if entry[:lastmod].present?
            xml.changefreq entry[:changefreq]
            xml.priority format("%.1f", entry[:priority])
          end
        end
      end
      xml.target!
    end

    private

    def sitemap_entries
      entries = []
      entries.concat(seo_setting_entries)
      entries.concat(property_entries)
      entries.concat(landing_page_entries)
      entries
    end

    def seo_setting_entries
      SeoSetting.where(active: true, apply_to_public: true, robots_index: true)
                .where.not(canonical_url: [nil, ""])
                .order(access_count: :desc, updated_at: :desc)
                .filter_map do |seo|
        add_entry(
          loc: seo.public_url(@base_url),
          lastmod: seo.updated_at,
          changefreq: changefreq_for(seo.page_type),
          priority: priority_for(seo.page_type)
        )
      end
    end

    def property_entries
      Habitation.active.includes(:rich_text_descricao_web).find_each.filter_map do |habitation|
        next unless habitation.publicly_viewable?

        path = @url_helpers.habitation_path(habitation)
        add_entry(
          loc: absolute_url(path),
          lastmod: habitation.updated_at,
          changefreq: "weekly",
          priority: habitation.empreendimento? ? 0.8 : 0.7
        )
      end
    end

    def landing_page_entries
      return [] unless defined?(LandingPage)

      LandingPage.where(active: true).find_each.filter_map do |page|
        path = @url_helpers.public_landing_page_path(page.slug)
        add_entry(
          loc: absolute_url(path),
          lastmod: page.updated_at,
          changefreq: "monthly",
          priority: 0.6
        )
      end
    end

    def add_entry(loc:, lastmod:, changefreq:, priority:)
      normalized = loc.to_s.split("#").first
      return if normalized.blank? || @seen.include?(normalized)

      @seen << normalized
      {
        loc: normalized,
        lastmod: lastmod,
        changefreq: changefreq,
        priority: priority
      }
    end

    def absolute_url(value)
      value = value.to_s
      if value.start_with?("http://", "https://")
        begin
          uri = URI.parse(value)
          path = uri.path.presence || "/"
          query = uri.query.present? ? "?#{uri.query}" : ""
          return "#{@base_url}#{path}#{query}"
        rescue URI::InvalidURIError
          return @base_url
        end
      end

      "#{@base_url}#{value.start_with?("/") ? value : "/#{value}"}"
    end

    def changefreq_for(page_type)
      case page_type.to_s
      when "property_listing", "property_landing", "developments_index", "development_landing" then "daily"
      when "property_show", "development_show" then "weekly"
      when "home_index" then "daily"
      else "monthly"
      end
    end

    def priority_for(page_type)
      case page_type.to_s
      when "property_listing", "property_landing", "developments_index", "development_landing" then 0.9
      when "home_index" then 1.0
      when "property_show", "development_show" then 0.8
      else 0.6
      end
    end
  end
end
