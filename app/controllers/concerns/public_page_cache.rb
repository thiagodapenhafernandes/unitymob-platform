# Cache do HTML completo de páginas públicas anônimas (hoje: home).
#
# Sem atraso: a chave inclui a versão da conta (PublicSite::PageVersion), que sobe no
# commit de qualquer registro que apareça na página, e o estado do blog (publicação
# agendada não escreve no banco). O TTL de MAX_AGE é só rede de segurança caso alguma
# dependência escape da lista de modelos: o pior caso fica igual ao de antes do cache.
#
# Modo por conta, em Admin > Site público > Desempenho (Setting "site_cache.mode"):
# off (padrão) | shadow ("Teste": renderiza sempre e compara com o cacheado, contando
# divergências) | on (serve do cache). Sem variável de ambiente.
#
# Por visitante, fora do HTML compartilhado: token CSRF (trocado no serve), consentimento
# LGPD (na chave), flash e admin logado (não usam cache) e o registro de visita de SEO
# (refeito a cada acerto, só com consentimento, como antes).
module PublicPageCache
  extend ActiveSupport::Concern

  MODES = %w[off shadow on].freeze
  MODE_LABELS = { "off" => "Desativado", "shadow" => "Em teste", "on" => "Ativo" }.freeze
  MAX_AGE = 10.minutes
  CSRF_PLACEHOLDER = "__PUBLIC_PAGE_CSRF__".freeze
  CSRF_META = /(<meta name="csrf-token" content=")[^"]*(")/
  PAGE_URL_PLACEHOLDER = "__PUBLIC_PAGE_URL__".freeze
  PAGE_URL_INPUT = /(<input[^>]*name="page_url"[^>]*value=")[^"]*(")/
  CSRF_INPUT = /(<input[^>]*name="authenticity_token"[^>]*value=")[^"]*(")/

  MODE_SETTING_KEY = "site_cache.mode".freeze

  def self.mode(tenant)
    value = Setting.tenant_get(MODE_SETTING_KEY, "off", tenant: tenant).to_s.downcase
    MODES.include?(value) ? value : "off"
  rescue StandardError
    "off"
  end

  def self.normalize(html)
    html.gsub(PAGE_URL_INPUT) { "#{$1}#{PAGE_URL_PLACEHOLDER}#{$2}" }.gsub(CSRF_META) { "#{$1}#{CSRF_PLACEHOLDER}#{$2}" }.gsub(CSRF_INPUT) { "#{$1}#{CSRF_PLACEHOLDER}#{$2}" }
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
    mode = PublicPageCache.mode(public_tenant)
    key = public_page_cache_key unless mode == "off"
    entry = read_public_page_entry(key) if key

    if mode == "on" && entry
      serve_cached_public_page(entry)
      return
    end

    @public_page_canonical_url = "#{request.base_url}#{request.path}" if key
    load_layout_settings
    block.call
    store_public_page(key, entry, mode) if key
  end

  def public_page_cache_key
    return unless request.get? && request.format.html? && !request.xhr?
    return if request.headers["Turbo-Frame"].present?
    return unless request.query_parameters.keys.all? { |name| name.match?(Seo::PageIdentity::TRACKING_PARAMS) }
    return if flash.any? || current_admin_user.present?

    tenant = public_tenant
    version = PublicSite::PageVersion.current(tenant.id)
    return if version.blank?

    ["public_page/v2", tenant.id, request.host, request.path, public_page_consent_state, version, public_page_blog_stamp(tenant)].join("/")
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
    PublicSite::PageCacheStats.record(public_tenant.id, :hit)
    html = entry[:html].gsub(CSRF_PLACEHOLDER) { form_authenticity_token }
      .gsub(PAGE_URL_PLACEHOLDER) { ERB::Util.html_escape(request.original_url) }
    render html: html.html_safe, layout: false
    Seo::PageTracker.record_visit!(self)
  end

  def store_public_page(key, previous, mode)
    return unless response.status == 200 && response.media_type == "text/html"

    html = PublicPageCache.normalize(response.body)
    if mode == "shadow" && previous && previous[:html] != html
      summary = public_page_diff_summary(previous[:html], html)
      Rails.logger.warn("[public_page_cache][shadow] DIVERGENCIA key=#{key} #{summary}")
      PublicSite::PageCacheStats.record(public_tenant.id, :diverged, detail: summary)
    elsif mode == "shadow" && previous
      Rails.logger.info("[public_page_cache][shadow] igual key=#{key}")
      PublicSite::PageCacheStats.record(public_tenant.id, :equal)
    elsif mode == "on"
      PublicSite::PageCacheStats.record(public_tenant.id, :miss)
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
