class SitemapsController < ApplicationController
  def show
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
    base_url = public_tenant.public_base_url(fallback_base_url: request.base_url)
    key = Seo::SitemapCache.key(tenant: public_tenant, base_url: base_url)
    content = Seo::SitemapCache.fetch(tenant_id: public_tenant.id, key: key) {
      Seo::SitemapBuilder.new(
        base_url: base_url,
        url_helpers: Rails.application.routes.url_helpers,
        tenant: public_tenant,
        habitation_scope: public_habitations
      ).to_xml
    }
    render xml: content if stale?(etag: content, public: true)
  end
end
