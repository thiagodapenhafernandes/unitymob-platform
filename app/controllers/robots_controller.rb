class RobotsController < ApplicationController
  skip_before_action :apply_seo_redirect

  def show
    render plain: robots_content, content_type: "text/plain"
  end

  private

  def robots_content
    base_url = public_tenant.public_base_url(fallback_base_url: request.base_url)

    <<~ROBOTS
      User-agent: *
      Disallow: /admin/
      Disallow: /rails/
      Disallow: /imoveis?page=
      Disallow: /imoveis?*page=
      Crawl-delay: 5

      Sitemap: #{base_url}/sitemap.xml
    ROBOTS
  end
end
