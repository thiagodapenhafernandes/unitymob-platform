module BlogArticlePresentation
  extend ActiveSupport::Concern

  private

  def prepare_blog_article
    @page_name = "blog"
    @page_title = @blog_article.meta_title.presence || @blog_article.title
    @page_description = @blog_article.meta_description.presence || @blog_article.excerpt.presence || @blog_article.content.to_plain_text.truncate(160)
    @canonical_url = @blog_article.public_url(fallback_base_url: request.base_url)
    @page_image = helpers.url_for(@blog_article.cover) if @blog_article.cover.attached?
    @related_articles = @blog_article.tenant.blog_articles.publicly_visible.where.not(id: @blog_article.id).recent.with_attached_cover.includes(:blog_categories).limit(3)
  end
end
