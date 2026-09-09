class BlogController < ApplicationController
  def index
    @page_name = "blog"
    @page_title = "Blog | #{@layout_setting.site_name}"
    @page_description = "Artigos da #{@layout_setting.site_name} sobre regiões, imóveis e mercado imobiliário."
    scope = public_tenant.blog_articles.publicly_visible
    @categories = public_tenant.blog_categories.where(id: BlogCategorization.where(blog_article_id: scope.select(:id)).select(:blog_category_id)).order(:name)
    if params[:slug].present?
      @category = public_tenant.blog_categories.find_by!(slug: params[:slug])
      scope = scope.joins(:blog_categorizations).where(blog_categorizations: { blog_category_id: @category.id })
      @page_title = "#{@category.name} | Blog #{@layout_setting.site_name}"
      @page_description = "Artigos sobre #{@category.name} no blog da #{@layout_setting.site_name}."
    end
    @articles = scope.matching(params[:q]).recent.with_attached_cover.includes(:blog_categories).paginate(page: params[:page], per_page: 12)
    page = @articles.current_page
    @page_title += " | Página #{page}" if page > 1
    @page_robots = params[:q].present? || @articles.empty? ? "noindex, follow" : "index, follow, max-image-preview:large"
    @canonical_url = public_tenant.public_base_url(fallback_base_url: request.base_url) + (@category ? blog_category_path(@category.slug) : blog_path)
    @canonical_url += "?page=#{page}" if page > 1
    if (cover_article = @articles.detect { |article| article.cover.attached? })
      @page_image = public_tenant.public_base_url(fallback_base_url: request.base_url) + helpers.blog_image_url(cover_article.cover, size: [1600, 1000])
    end
  end
end
