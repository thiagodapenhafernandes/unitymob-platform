class SitemapsController < ApplicationController
  def show
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
    render xml: Rails.cache.fetch(Habitation.public_sitemap_cache_key(public_tenant.id, request.base_url), expires_in: 30.minutes) {
      Seo::SitemapBuilder.new(
        base_url: request.base_url,
        url_helpers: Rails.application.routes.url_helpers,
        tenant: public_tenant,
        habitation_scope: public_habitations
      ).to_xml
    }
  end
end
