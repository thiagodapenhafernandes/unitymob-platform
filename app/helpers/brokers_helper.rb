module BrokersHelper
  # Página pública do corretor: usa a rota curinga /:slug (landing), com
  # fallback para o corretor quando não há landing nem artigo com o slug.
  def broker_site_path(broker)
    public_landing_page_path(broker.site_slug)
  end
end
