module PublicSite
  # Versão do HTML público por conta. Quem altera algo que aparece nas páginas
  # (configurações, banners, imóveis, seções) chama bump no after_commit; a chave
  # do cache de página (PublicPageCache) inclui esta versão, então a mudança vale
  # no próximo acesso, sem esperar TTL. Se o Redis perder a chave, nasce um token
  # novo: custa um cache miss, nunca conteúdo velho.
  module PageVersion
    module_function

    def current(tenant_id)
      Rails.cache.fetch(key(tenant_id)) { new_token }
    rescue StandardError => e
      Rails.logger.warn("[public_page_version] leitura falhou tenant_id=#{tenant_id} #{e.class}: #{e.message}")
      nil
    end

    def bump(tenant_id)
      return if tenant_id.blank?

      Rails.cache.write(key(tenant_id), new_token)
    rescue StandardError => e
      Rails.logger.warn("[public_page_version] bump falhou tenant_id=#{tenant_id} #{e.class}: #{e.message}")
    end

    # Mudança sem dono (configuração global da plataforma): vale para todas as contas.
    def bump_all
      Tenant.unscoped.pluck(:id).each { |tenant_id| bump(tenant_id) }
    end

    def key(tenant_id)
      "public_page_version/v1/tenant/#{tenant_id}"
    end

    def new_token
      SecureRandom.hex(6)
    end
  end
end
