require "uri"

class SeoSetting < ApplicationRecord
  include TenantScoped
  AI_STATUSES = %w[pending generating generated failed skipped].freeze
  PAGE_TYPE_LABELS = {
    "property_show" => "Imóvel",
    "property_listing" => "Busca de imóveis",
    "development_show" => "Empreendimento",
    "landing_pages_show" => "Landing page",
    "developments_index" => "Busca de empreendimentos",
    "empreendimentos_index" => "Busca de empreendimentos",
    "development_landing" => "Landing de empreendimento",
    "property_landing" => "Landing de imóveis",
    "pages_corporativos" => "Página corporativa",
    "home" => "Home",
    "home_index" => "Home",
    "legacy" => "Legado"
  }.freeze

  # ActiveStorage for OG image
  has_one_attached :og_image_file
  has_many :focus_keywords, -> { ordered }, class_name: "SeoFocusKeyword", dependent: :destroy
  has_many :change_logs, -> { recent }, class_name: "SeoChangeLog", dependent: :destroy
  has_many :page_visits, class_name: "SeoPageVisit", dependent: :destroy
  has_many :marketing_campaigns, dependent: :nullify
  has_many :seo_conversion_events, dependent: :nullify
  
  # Validations
  validates :page_name, presence: true, uniqueness: { scope: :tenant_id }
  validates :canonical_key, presence: true, uniqueness: { scope: :tenant_id }
  validates :ai_status, inclusion: { in: AI_STATUSES }

  before_validation :ensure_canonical_key
  before_validation :sanitize_urls
  before_save :refresh_seo_score
  after_update :record_change_log
  
  # Find by page with caching
  def self.for_page(page_name, tenant: Current.tenant)
    return new(page_name: page_name) unless tenant

    Rails.cache.fetch("seo_setting_tenant_#{tenant.id}_#{page_name}", expires_in: 24.hours) do
      where(tenant: tenant).find_by(page_name: page_name) || new(page_name: page_name, tenant: tenant)
    end
  end

  def self.for_canonical_key(canonical_key, tenant: Current.tenant)
    return if canonical_key.blank? || tenant.blank?

    Rails.cache.fetch("seo_setting_tenant_#{tenant.id}_#{canonical_key}", expires_in: 24.hours) do
      where(tenant: tenant).find_by(canonical_key: canonical_key)
    end
  end

  def self.page_type_label_for(page_type)
    type = page_type.to_s.presence
    PAGE_TYPE_LABELS.fetch(type, type.to_s.tr("_", " ").presence&.humanize || "Sem tipo")
  end

  def public_applicable?
    active? && apply_to_public?
  end

  def robots_content
    "#{robots_index? ? "index" : "noindex"}, #{robots_follow? ? "follow" : "nofollow"}"
  end

  def score_label
    case seo_score.to_i
    when 85..100 then "Ótimo"
    when 70..84 then "Bom"
    when 50..69 then "Atenção"
    else "Fraco"
    end
  end

  def page_type_label
    self.class.page_type_label_for(page_type)
  end

  def register_access!
    increment!(:access_count)
    update_column(:last_accessed_at, Time.current)
  end

  def display_name
    meta_title.presence || og_title.presence || page_name
  end

  def focus_keyword_list
    focus_keywords.map(&:keyword).join(", ")
  end

  def focus_keyword_list=(value)
    @focus_keyword_list = value
  end

  def sync_focus_keywords!(value = @focus_keyword_list)
    keywords = value.to_s.split(",").map(&:squish).reject(&:blank?).map(&:downcase).uniq.first(5)
    transaction do
      focus_keywords.where.not(keyword: keywords).destroy_all
      keywords.each_with_index do |keyword, index|
        focus_keywords.find_or_initialize_by(keyword: keyword).tap do |record|
          record.position = index
          record.save!
        end
      end
    end
  end

  def public_url(base_url)
    base = base_url.to_s.delete_suffix("/")
    path = sanitized_canonical_path.presence || canonical_path.presence || "/"
    path.start_with?("http") ? sanitize_url(path, base_url: base) : "#{base}#{path.start_with?("/") ? path : "/#{path}"}"
  end

  def social_image_url(base_url:, page_image: nil, fallback_image: "/icon.png")
    base = base_url.to_s.delete_suffix("/")
    source = page_image.presence ||
             attached_og_image_path.presence ||
             related_habitation_image_url.presence ||
             fallback_image

    absolute_url(source, base)
  end

  def sanitized_canonical_path
    sanitize_path(canonical_path.presence || canonical_url)
  end

  # Clear cache after update
  after_commit :clear_seo_cache

  private

  def ensure_canonical_key
    self.canonical_key = page_name if canonical_key.blank?
  end

  def sanitize_urls
    sanitized_path = sanitized_canonical_path
    self.canonical_path = sanitized_path if sanitized_path.present?

    if canonical_url.present?
      self.canonical_url = sanitize_url(canonical_url, base_url: nil)
    elsif sanitized_path.present?
      self.canonical_url = sanitized_path
    end
  end

  def refresh_seo_score
    self.seo_score = Seo::Analyzer.new(self).score
  end

  def clear_seo_cache
    Rails.cache.delete("seo_setting_tenant_#{tenant_id}_#{page_name}")
    Rails.cache.delete("seo_setting_tenant_#{tenant_id}_#{canonical_key}")
    Footer::QuickLinksService.clear_cache if defined?(Footer::QuickLinksService)
  end

  def record_change_log
    tracked = saved_changes.slice(
      "meta_title",
      "meta_description",
      "meta_keywords",
      "intro_text",
      "og_title",
      "og_description",
      "canonical_url",
      "canonical_path",
      "robots_index",
      "robots_follow",
      "active",
      "apply_to_public",
      "manual_mode",
      "seo_score"
    )
    return if tracked.blank?

    change_logs.create!(
      admin_user: Current.admin_user,
      event_type: ai_generated_at_previously_changed? ? "ai_generate" : "update",
      changed_fields: tracked.transform_values { |before, after| { from: before, to: after } },
      snapshot: seo_snapshot
    )
  end

  def seo_snapshot
    {
      meta_title: meta_title,
      meta_description: meta_description,
      meta_keywords: meta_keywords,
      intro_text: intro_text,
      og_title: og_title,
      og_description: og_description,
      canonical_path: canonical_path,
      robots: robots_content,
      seo_score: seo_score
    }
  end

  def attached_og_image_path
    return unless og_image_file.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_path(og_image_file, only_path: true)
  end

  def related_habitation_image_url
    habitation = related_habitation
    return if habitation.blank?

    habitation.primary_image_url.presence || habitation.image_urls.first
  end

  def related_habitation
    identifier = canonical_key.to_s[/\Aproperty:(.+)\z/, 1].presence || path_identifier
    return if identifier.blank?

    tenant_habitations = Current.tenant&.habitations
    return if tenant_habitations.nil?

    tenant_habitations.find_by(codigo: identifier) ||
      tenant_habitations.find_by(id: identifier) ||
      tenant_habitations.find_by(slug: identifier)
  end

  def path_identifier
    path = sanitized_canonical_path.to_s.split("?").first.to_s
    match_data = path.match(%r{\A/(?:imoveis|imovel)/([^/]+)\z})
    return if match_data.blank?

    URI.decode_www_form_component(match_data[1].to_s)
  rescue ArgumentError
    match_data&.[](1).to_s.presence
  end

  def absolute_url(source, base)
    source = source.to_s
    return source.sub("http://", "https://") if source.start_with?("http://")
    return source if source.start_with?("https://")

    "#{base}#{source.start_with?("/") ? source : "/#{source}"}"
  end

  def sanitize_url(value, base_url:)
    uri = URI.parse(value.to_s)
    path = sanitize_path("#{uri.path}#{uri.query.present? ? "?#{uri.query}" : ""}")
    return path if base_url.blank?

    "#{base_url}#{path}"
  rescue URI::InvalidURIError
    value.to_s
  end

  def sanitize_path(value)
    value = value.to_s
    return if value.blank?

    uri = URI.parse(value.start_with?("http") ? value : "https://example.com#{value.start_with?("/") ? value : "/#{value}"}")
    path = uri.path.presence || "/"
    pairs = URI.decode_www_form(uri.query.to_s)
               .filter_map do |key, val|
                 clean_key = key.to_s.delete_suffix("[]")
                 next if clean_key.match?(Seo::PageIdentity::IGNORED_PARAMS)
                 next if val.blank?

                 [clean_key, val.to_s.strip]
               end
               .sort

    query = pairs.any? ? "?#{URI.encode_www_form(pairs)}" : ""
    "#{path}#{query}"
  rescue URI::InvalidURIError
    value
  end
end
