module PublicSite
  # Contadores do cache de página por conta (exibidos em Admin > Site público > Desempenho).
  # hit/miss: modo ativo; equal/diverged: modo teste (comparação com a página renderizada).
  module PageCacheStats
    EVENTS = %i[hit miss equal diverged].freeze
    TTL = 7.days

    module_function

    def record(tenant_id, event, detail: nil)
      key = counter_key(tenant_id, event)
      count = Rails.cache.increment(key, 1, expires_in: TTL)
      Rails.cache.write(key, 1, expires_in: TTL, raw: true) if count.nil?
      Rails.cache.write(detail_key(tenant_id), detail.to_s.first(600), expires_in: TTL) if event == :diverged && detail.present?
    rescue StandardError => e
      Rails.logger.warn("[public_page_cache_stats] #{e.class}: #{e.message}")
    end

    def snapshot(tenant_id)
      EVENTS.index_with { |event| Rails.cache.read(counter_key(tenant_id, event), raw: true).to_i }
            .merge(last_divergence: Rails.cache.read(detail_key(tenant_id)))
    end

    def reset(tenant_id)
      EVENTS.each { |event| Rails.cache.delete(counter_key(tenant_id, event)) }
      Rails.cache.delete(detail_key(tenant_id))
    end

    def counter_key(tenant_id, event) = "public_page_cache/stats/v1/tenant/#{tenant_id}/#{event}"
    def detail_key(tenant_id) = "public_page_cache/stats/v1/tenant/#{tenant_id}/last_divergence"
  end
end
