module Admin
  # Liga/desliga o cache de HTML do site público da conta e mostra se ele está seguro para ativar.
  class SiteCachesController < BaseController
    requires_permission :manage, :site_publico

    def show
      @mode = PublicPageCache.mode(current_tenant)
      @stats = PublicSite::PageCacheStats.snapshot(current_tenant.id)
    end

    def update
      mode = params[:mode].to_s
      return redirect_to(admin_site_cache_path, alert: "Modo inválido.") unless PublicPageCache::MODES.include?(mode)

      Setting.set(PublicPageCache::MODE_SETTING_KEY, mode, nil, tenant: current_tenant)
      PublicSite::PageCacheStats.reset(current_tenant.id) if mode == "shadow"
      PublicSite::PageVersion.bump(current_tenant.id)
      redirect_to admin_site_cache_path, notice: "Cache do site: #{PublicPageCache::MODE_LABELS.fetch(mode).downcase}."
    end

    # Descarta o HTML guardado agora (as próximas visitas remontam a página).
    def clear
      PublicSite::PageVersion.bump(current_tenant.id)
      redirect_to admin_site_cache_path, notice: "Cache do site limpo."
    end
  end
end
