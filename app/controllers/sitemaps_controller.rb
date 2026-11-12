class SitemapsController < ApplicationController
  skip_before_action :load_layout_settings

  def show
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
    base_url = public_tenant.public_base_url(fallback_base_url: request.base_url)
    content = Seo::SitemapCache.fetch(tenant: public_tenant, base_url: base_url)
    unless content
      response.headers["Retry-After"] = "30"
      response.headers["Cache-Control"] = "no-store"
      return head :service_unavailable
    end

    render xml: content if stale?(etag: content, public: true)
  end
end
