module BlogHelper
  def blog_article_path(article)
    public_landing_page_path(article.slug)
  end

  def blog_image_url(source, size:)
    url = public_image_url(source, resize_to_limit: size, format: :webp, force_variant: true, representation_proxy: true)
    # Cached HTML must never contain expiring Spaces URLs. Keep objects private.
    url.to_s.start_with?("/") ? url : rails_storage_proxy_path(source.respond_to?(:blob) ? source.blob : source, only_path: true)
  end

  def blog_cover(article, hero: false)
    return unless article.cover.attached?

    image_tag blog_image_url(article.cover, size: hero ? [1600, 1000] : [640, 420]),
      alt: article.cover_alt.presence || article.title, width: hero ? 1600 : 640, height: hero ? 900 : 360,
      loading: hero ? "eager" : "lazy", fetchpriority: hero ? "high" : "auto", class: "blog-image"
  end

  def blog_article_body(article)
    body = article.content.body
    return ["".html_safe, []] unless body

    html = body.render_attachments do |attachment|
      blob = attachment.attachable
      next "" unless Blog::Storage.owned?(blob, article.tenant_id)
      render "blog/attachment", blob: blob, caption: attachment.caption
    end.to_html
    fragment = Nokogiri::HTML.fragment(html)
    fragment.css("[style]").each do |span|
      size = span["style"][/font-size:\s*(0\.85em|1\.25em)/, 1]
      span["class"] = size == "0.85em" ? "ax-text-small" : "ax-text-large" if size
    end
    headings = fragment.css("h1,h2,h3,h4,h5,h6").select { |node| node.text.strip.present? }
    top_level = headings.map { |node| node.name.delete_prefix("h").to_i }.min
    toc = headings.select { |node| node.name == "h#{top_level}" }.each_with_index.map do |heading, index|
      heading["id"] = "secao-#{index + 1}"
      [heading.text, heading["id"]]
    end
    [sanitize(fragment.to_html, tags: %w[p br div span strong b em i u s del h1 h2 h3 h4 h5 h6 ul ol li blockquote pre code hr a figure figcaption img action-text-attachment], attributes: %w[href src alt width height loading decoding class id target rel]), toc]
  end
end
