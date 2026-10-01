# Cache do HTML completo de páginas públicas anônimas (hoje: home).
#
# Sem atraso: a chave inclui a versão da conta (PublicSite::PageVersion), que sobe no
# commit de qualquer registro que apareça na página, e o estado do blog (publicação
# agendada não escreve no banco). O TTL de MAX_AGE é só rede de segurança caso alguma
# dependência escape da lista de modelos: o pior caso fica igual ao de antes do cache.
#
# PUBLIC_PAGE_CACHE: off (padrão) | shadow (renderiza sempre e compara com o cacheado,
# logando divergências) | on (serve do cache).
#
# Por visitante, fora do HTML compartilhado: token CSRF (trocado no serve), consentimento
# LGPD (na chave), flash e admin logado (não usam cache) e o registro de visita de SEO
# (refeito a cada acerto, só com consentimento, como antes).
module PublicPageCache
  extend ActiveSupport::Concern

  MODES = %w[off shadow on].freeze
  MAX_AGE = 10.minutes
  CSRF_PLACEHOLDER = "__PUBLIC_PAGE_CSRF__".freeze
  CSRF_META = /(<meta name="csrf-token" content=")[^"]*(")/
  CSRF_INPUT = /(<input[^>]*name="authenticity_token"[^>]*value=")[^"]*(")/

  def self.mode
    value = ENV["PUBLIC_PAGE_CACHE"].to_s.downcase
    MODES.include?(value) ? value : "off"
  end

  def self.normalize(html)
    html.gsub(CSRF_META) { "#{$1}#{CSRF_PLACEHOLDER}#{$2}" }.gsub(CSRF_INPUT) { "#{$1}#{CSRF_PLACEHOLDER}#{$2}" }
  end

  class_methods do
    # Chamar depois de skip_before_action :load_layout_settings: o cache decide antes
    # de pagar as consultas de layout, que só rodam no miss.
    def public_page_cache(*actions)
      around_action :cache_public_page, only: actions
    end
  end

  private

  def cache_public_page(&block)
    mode = PublicPageCache.mode
    key = public_page_cache_key unless mode == "off"
    entry = read_public_page_entry(key) if key

    if mode == "on" && entry
      serve_cached_public_page(entry)
      return
    end

    load_layout_settings
    block.call
    store_public_page(key, entry, mode) if key
  end

  def public_page_cache_key
    return unless request.get? && request.format.html? && !request.xhr?
    return if request.query_string.present? || request.headers["Turbo-Frame"].present?
    return if flash.any? || current_admin_user.present?

    tenant = public_tenant
    version = PublicSite::PageVersion.current(tenant.id)
    return if version.blank?

    ["public_page/v1", tenant.id, request.host, request.path, public_page_consent_state, version, public_page_blog_stamp(tenant)].join("/")
  end

  def public_page_consent_state
    value = cookies[ApplicationController::LGPD_CONSENT_COOKIE].to_s
    %w[accepted rejected].include?(value) ? value : "none"
  end

  # Artigo agendado passa a aparecer sem nenhuma gravação: a consulta entra na chave.
  def public_page_blog_stamp(tenant)
    rows = tenant.blog_articles.publicly_visible.recent.limit(3).pluck(:id, :updated_at)
    Digest::SHA1.hexdigest(rows.map { |id, updated_at| [id, updated_at&.utc&.strftime("%s%6N")] }.to_json)[0, 10]
  end

  def read_public_page_entry(key)
    Rails.cache.read(key)
  rescue StandardError => e
    Rails.logger.warn("[public_page_cache] leitura falhou #{e.class}: #{e.message}")
    nil
  end

  def serve_cached_public_page(entry)
    response.headers["Cache-Control"] = entry[:cache_control] if entry[:cache_control].present?
    response.headers["X-Public-Page-Cache"] = "hit"
    html = entry[:html].gsub(CSRF_PLACEHOLDER) { form_authenticity_token }
    render html: html.html_safe, layout: false
    Seo::PageTracker.record_visit!(self)
  end

  def store_public_page(key, previous, mode)
    return unless response.status == 200 && response.media_type == "text/html"

    html = PublicPageCache.normalize(response.body)
    if mode == "shadow" && previous && previous[:html] != html
      Rails.logger.warn("[public_page_cache][shadow] DIVERGENCIA key=#{key} #{public_page_diff_summary(previous[:html], html)}")
    elsif mode == "shadow" && previous
      Rails.logger.info("[public_page_cache][shadow] igual key=#{key}")
    end
    response.headers["X-Public-Page-Cache"] = previous ? "shadow-compared" : "miss" if mode != "off"
    Rails.cache.write(key, { html: html, cache_control: response.headers["Cache-Control"] }, expires_in: MAX_AGE)
  rescue StandardError => e
    Rails.logger.warn("[public_page_cache] gravação falhou #{e.class}: #{e.message}")
  end

  def public_page_diff_summary(old_html, new_html)
    index = old_html.chars.zip(new_html.chars).index { |a, b| a != b } || [old_html.length, new_html.length].min
    "bytes=#{old_html.bytesize}->#{new_html.bytesize} primeira_diferenca_em=#{index} antes=#{old_html[[index - 40, 0].max, 120].inspect} depois=#{new_html[[index - 40, 0].max, 120].inspect}"
  end
end
