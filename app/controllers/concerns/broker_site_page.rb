module BrokerSitePage
  extend ActiveSupport::Concern

  private

  # Monta a página pública do corretor (cabeçalho + listagem filtrável dos
  # imóveis dele, mesmo motor de busca/filtros/grade da listagem). Requer
  # @broker. Renderiza o frame da grade e retorna true, ou prepara os ivars
  # e retorna false para a action renderizar brokers/show. Servido pelo
  # fallback /:slug (landing > artigo > corretor).
  def setup_broker_site_page
    filter_params = search_params
    return true if reject_invalid_public_listing_page!

    listing_scope = public_tenant.habitations
      .public_property_listable
      .by_broker(@broker)
      .advanced_search(filter_params)
    total_entries = cached_listing_total_entries(listing_scope, filter_params, namespace: "broker/#{@broker.id}")
    return true if reject_public_listing_page_beyond_total!(total_entries)

    @habitations = listing_scope
      .includes(*PublicListingSearch::PUBLIC_LISTING_INCLUDES)
      .paginate(page: requested_public_listing_page, per_page: PublicListingSearch::PUBLIC_LISTING_PER_PAGE, total_entries: total_entries)
    @filter_params = filter_params
    load_filter_options
    @home_setting ||= HomeSetting.instance(tenant: public_tenant)
    # A página renderiza o próprio shell do drawer global (com submit no corretor);
    # sem isso o layout montaria um segundo drawer global (submit em /imoveis).
    @hide_global_search = true
    assign_broker_page_seo
    PublicSite::CardPhotoPreloader.new(@habitations.to_a, limit: 3).call

    if turbo_frame_request_id == "public-listing-grid"
      render partial: "habitations/listing_grid", layout: false
      return true
    end

    false
  end

  def assign_broker_page_seo
    site_name = @layout_setting&.site_name.presence || public_tenant.name
    @page_name = "corretor"
    @page_title = "Imóveis de #{@broker.name} | #{site_name}"
    @page_description = @broker.biography.presence || "Imóveis à venda e para alugar com #{@broker.name} (#{@broker.creci}). Fale direto com o corretor."
    @canonical_url = "#{public_tenant.public_base_url(fallback_base_url: request.base_url)}#{public_landing_page_path(@broker.site_slug)}"
    @listing_heading = "Imóveis de #{@broker.name.split.first}"
  end
end
