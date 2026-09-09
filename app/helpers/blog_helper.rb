module BlogHelper
  def blog_structured_data
    base = public_tenant.public_base_url(fallback_base_url: request.base_url)
    organization = { "@type" => "Organization", "name" => @layout_setting.site_name, "url" => base }
    breadcrumbs = [{ "@type" => "ListItem", "position" => 1, "name" => "Blog", "item" => "#{base}#{blog_path}" }]
    page = {
      "@type" => @blog_article ? "BlogPosting" : "CollectionPage",
      "@id" => @canonical_url, "url" => @canonical_url,
      "name" => @page_title, "description" => @page_description,
      "inLanguage" => "pt-BR", "publisher" => organization,
      "isPartOf" => { "@type" => "Blog", "@id" => "#{base}#{blog_path}#blog", "name" => "Blog #{@layout_setting.site_name}", "url" => "#{base}#{blog_path}" }
    }
    page["image"] = @page_image if @page_image.present?
    if @blog_article
      page.merge!(
        "headline" => @blog_article.title,
        "datePublished" => @blog_article.published_at&.iso8601,
        "dateModified" => @blog_article.updated_at.iso8601,
        "mainEntityOfPage" => { "@type" => "WebPage", "@id" => @canonical_url },
        "author" => organization,
        "articleSection" => @blog_article.blog_categories.map(&:name),
        "wordCount" => @blog_article.content.to_plain_text.split.size
      )
      breadcrumbs << { "@type" => "ListItem", "position" => 2, "name" => @blog_article.title, "item" => @canonical_url }
    else
      page["mainEntity"] = {
        "@type" => "ItemList",
        "itemListElement" => @articles.each_with_index.map do |article, index|
          { "@type" => "ListItem", "position" => @articles.offset + index + 1,
            "name" => article.title, "url" => article.public_url(fallback_base_url: request.base_url) }
        end
      }
      breadcrumbs << { "@type" => "ListItem", "position" => 2, "name" => @category.name, "item" => "#{base}#{blog_category_path(@category.slug)}" } if @category
    end
    graph = [page.compact]
    graph << { "@type" => "BreadcrumbList", "itemListElement" => breadcrumbs } if breadcrumbs.size > 1
    { "@context" => "https://schema.org", "@graph" => graph }
  end

  def blog_article_path(article)
    public_landing_page_path(article.slug)
  end

  def blog_image_url(source, size:)
    blob = source.respond_to?(:blob) ? source.blob : source
    # Generate a signed route only: no Spaces HEAD requests or image processing while rendering HTML.
    image = blob.variable? ? blob.variant(resize_to_limit: size, format: :webp) : blob
    rails_storage_proxy_path(image, only_path: true)
  end

  def blog_cover(article, hero: false, archive: false)
    return unless article.cover.attached?

    image_tag blog_image_url(article.cover, size: hero ? [1600, 1000] : [640, 420]),
      alt: article.cover_alt.presence || article.title, width: hero ? 1600 : 640, height: hero ? 900 : 360,
      srcset: hero ? "#{blog_image_url(article.cover, size: [640, 420])} 640w, #{blog_image_url(article.cover, size: [1600, 1000])} 1600w" : nil,
      sizes: hero ? (archive ? "(max-width: 767px) calc(100vw - 40px), 600px" : "(max-width: 767px) calc(100vw - 40px), (max-width: 1256px) calc(100vw - 72px), 1184px") : nil,
      decoding: "async", loading: hero ? "eager" : "lazy", fetchpriority: hero ? "high" : "auto", class: "blog-image"
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
