class LandingPagesController < ApplicationController
  include BlogArticlePresentation
  include LandingPageShowcases
  include PublicListingSearch
  include BrokerSitePage

  def show
    @landing_page = public_tenant.landing_pages.active.find_by(slug: params[:slug])
    unless @landing_page
      @blog_article = public_tenant.blog_articles.publicly_visible.with_rich_text_content_and_embeds.with_attached_cover.includes(:blog_categories).find_by(slug: params[:slug])
      if @blog_article
        prepare_blog_article
        return render "blog/show"
      end

      # Sem landing nem artigo: tenta a página pública do corretor (/:slug).
      @broker = AdminUser.site_broker_for(public_tenant, params[:slug])
      if @broker
        return if setup_broker_site_page

        return render "brokers/show"
      end

      return render_unavailable_page
    end

    assign_seo
    if @landing_page.blocks?
      prepare_blocks
      render :blocks
    else
      # Página ainda sem blocos (não convertida): segue a tela original até a limpeza final.
      prepare_legacy_listing
    end
  end

  private

  # Página que existe mas não está no ar (rascunho/inativa): volta à home com aviso. Sem página nenhuma, 404 como sempre.
  def render_unavailable_page
    page = public_tenant.landing_pages.find_by(slug: params[:slug])
    raise ActiveRecord::RecordNotFound, "Página não encontrada" unless page

    flash[:warning] = page.draft? ? "Esta página está em rascunho e ainda não foi publicada." : "Esta página está inativa no momento."
    redirect_to root_path
  end

  def assign_seo
    @page_title = @landing_page.meta_title.presence || @landing_page.title
    @page_description = @landing_page.meta_description.presence || @landing_page.description.presence
    # O que foi configurado na página vale mais que o SEO descoberto sozinho (que só copia o que existia na 1ª visita).
    # Só um SEO editado à mão no módulo de SEO (modo manual) continua mandando.
    @canonical_url = public_landing_page_url(@landing_page.slug) # o SEO automático guardava "/slug?slug=slug"
    @page_title_priority = true
    @page_description_priority = @page_description.present?
  end

  # Página montada por blocos: cada vitrine busca os próprios imóveis; só a vitrine interativa
  # recebe a paginação (?page=) e os filtros do visitante.
  def prepare_blocks
    @blocks = @landing_page.visible_blocks
    @showcases = build_showcases(@blocks, habitations: public_habitations)
  end

  def prepare_legacy_listing
    filters = @landing_page.filter_params || {}
    search_params = {
      category: filters["category"],
      city: filters["city"],
      neighborhood: filters["neighborhood"],
      development: filters["development"],
      property_codes: filters["property_codes"],
      transaction_type: filters["transaction_type"],
      min_bedrooms: filters["min_bedrooms"],
      min_suites: filters["min_suites"],
      min_parking: filters["min_parking"],
      target_price: filters["target_price"],
      min_area: filters["min_area"],
      opportunity: filters["opportunity"],
      characteristics: filters["characteristics"],
      caracteristica_unica: filters["caracteristica_unica"],
      status: filters["status"],
      sort: params[:sort].presence || filters["sort"]
    }

    @habitations = public_habitations
      .active
      .advanced_search(search_params)
      .includes(
        :address,
        { constructor: { logo_attachment: :blob } },
        { empreendimento: { constructor: { logo_attachment: :blob } } }
      )
      .paginate(page: params[:page], per_page: 12)
    PublicSite::CardPhotoPreloader.new(@habitations.to_a, limit: 3).call
  end
end
