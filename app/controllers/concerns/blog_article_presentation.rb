module BlogArticlePresentation
  extend ActiveSupport::Concern

  private

  def prepare_blog_article
    @page_name = "blog"
    @page_title = @blog_article.meta_title.presence || @blog_article.title
    @page_description = helpers.strip_tags(@blog_article.meta_description.presence || (@blog_article.excerpt.presence || @blog_article.content.to_plain_text).squish.truncate(160, separator: " ")).squish
    @canonical_url = @blog_article.public_url(fallback_base_url: request.base_url)
    @page_robots = "index, follow, max-image-preview:large"
    @page_robots = "noindex, nofollow" if controller_path.start_with?("admin/")
    @page_image = @blog_article.tenant.public_base_url(fallback_base_url: request.base_url) + helpers.blog_image_url(@blog_article.cover, size: [1600, 1000]) if @blog_article.cover.attached?
    @related_articles = @blog_article.tenant.blog_articles.publicly_visible.where.not(id: @blog_article.id).recent.with_attached_cover.includes(:blog_categories).limit(3)
  end
end
