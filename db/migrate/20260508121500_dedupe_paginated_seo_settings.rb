class DedupePaginatedSeoSettings < ActiveRecord::Migration[7.1]
  class SeoSettingRecord < ActiveRecord::Base
    self.table_name = "seo_settings"
  end

  def up
    dedupe_development_pages
    normalize_paginated_listing_paths
  end

  def down
    # Data cleanup is intentionally irreversible.
  end

  private

  def dedupe_development_pages
    canonical = SeoSettingRecord.find_or_initialize_by(canonical_key: "empreendimentos")
    paginated = SeoSettingRecord
                .where(page_type: "empreendimentos_index")
                .where("canonical_path LIKE ?", "/empreendimentos?page=%")

    first_source = paginated.order(:id).first

    canonical.assign_attributes(
      page_name: "empreendimentos",
      page_type: "developments_index",
      canonical_path: "/empreendimentos",
      canonical_url: "/empreendimentos",
      normalized_params: {},
      robots_index: true,
      robots_follow: true,
      active: true,
      apply_to_public: true,
      auto_discovered: true,
      access_count: canonical.access_count.to_i + paginated.sum(:access_count).to_i,
      last_accessed_at: [canonical.last_accessed_at, paginated.maximum(:last_accessed_at)].compact.max
    )

    if first_source.present?
      canonical.meta_title = first_source.meta_title if canonical.meta_title.blank?
      canonical.meta_description = first_source.meta_description if canonical.meta_description.blank?
      canonical.meta_keywords = first_source.meta_keywords if canonical.meta_keywords.blank?
      canonical.og_title = first_source.og_title if canonical.og_title.blank?
      canonical.og_description = first_source.og_description if canonical.og_description.blank?
      canonical.ai_status = first_source.ai_status if canonical.ai_status.blank?
      canonical.ai_insights = first_source.ai_insights if canonical.ai_insights.blank?
    end

    canonical.save!
    paginated.where.not(id: canonical.id).delete_all
  end

  def normalize_paginated_listing_paths
    SeoSettingRecord.where(page_type: "property_listing").find_each do |seo|
      next unless seo.canonical_path.to_s.include?("page=")

      seo.update_columns(
        canonical_path: remove_page_param(seo.canonical_path),
        canonical_url: remove_page_param(seo.canonical_url),
        robots_index: true,
        updated_at: Time.current
      )
    end

    SeoSettingRecord.where(page_type: "developments_index").find_each do |seo|
      next unless seo.canonical_path.to_s.include?("page=")

      seo.update_columns(
        canonical_path: remove_page_param(seo.canonical_path),
        canonical_url: remove_page_param(seo.canonical_url),
        robots_index: true,
        updated_at: Time.current
      )
    end
  end

  def remove_page_param(value)
    uri = URI.parse(value.to_s.start_with?("http") ? value.to_s : "https://example.com#{value.to_s.start_with?("/") ? value : "/#{value}"}")
    pairs = URI.decode_www_form(uri.query.to_s).reject { |key, _| key == "page" }
    query = pairs.any? ? "?#{URI.encode_www_form(pairs)}" : ""
    path = "#{uri.path.presence || "/"}#{query}"
    value.to_s.start_with?("http") ? "#{uri.scheme}://#{uri.host}#{path}" : path
  rescue URI::InvalidURIError
    value
  end
end
