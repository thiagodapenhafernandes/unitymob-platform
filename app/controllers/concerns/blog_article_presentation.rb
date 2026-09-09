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
    prepare_blog_social_image(@blog_article)
    @related_articles = @blog_article.tenant.blog_articles.publicly_visible.where.not(id: @blog_article.id).recent.with_attached_cover.includes(:blog_categories).limit(3)
  end

  def prepare_blog_social_image(article)
    return unless article&.cover&.attached?

    @page_image = article.tenant.public_base_url(fallback_base_url: request.base_url) + helpers.rails_storage_proxy_path(article.cover.variant(:blog_social), only_path: true)
    @page_image_type = "image/jpeg"
    @page_image_width = 1200
    @page_image_height = 630
    @page_image_alt = article.cover_alt.presence || article.title
  end

end
