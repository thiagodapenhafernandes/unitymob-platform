class LlmsController < ApplicationController
  skip_before_action :apply_seo_redirect, :load_layout_settings

  def show
    @identity = Tenants::PublicIdentity.new(public_tenant)
    @base_url = public_tenant.public_base_url(fallback_base_url: request.base_url)
    @articles = public_tenant.blog_articles.publicly_visible.recent.limit(5)
    content = Rails.cache.fetch(
      ["public_llms_v1", public_tenant.id, @base_url, PublicSite::PageVersion.current(public_tenant.id), @articles.cache_key_with_version],
      expires_in: 10.minutes
    ) do
      @footer = FooterSetting.instance(tenant: public_tenant)
      @contact = ContactSetting.instance(tenant: public_tenant)
      @profile = PublicSiteProfile.current(tenant: public_tenant)
      @cities = public_filter_location_options.select { |option| option[:type] == "city" }.map { |option| option[:label] }
      CGI.unescapeHTML(render_to_string(:show, formats: [:text], layout: false))
    end
    render plain: content, content_type: "text/plain; charset=utf-8" if stale?(etag: content, public: true)
  end
end
