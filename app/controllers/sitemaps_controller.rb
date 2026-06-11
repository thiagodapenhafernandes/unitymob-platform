class SitemapsController < ApplicationController
  def show
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
    render xml: Seo::SitemapBuilder.new(
      base_url: request.base_url,
      url_helpers: Rails.application.routes.url_helpers
    ).to_xml
  end
end
