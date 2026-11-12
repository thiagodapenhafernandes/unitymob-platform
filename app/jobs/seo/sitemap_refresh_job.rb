module Seo
  class SitemapRefreshJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: ->(tenant_id, base_url) { SitemapCache.snapshot_key(tenant_id, base_url).join("/") }, duration: 10.minutes, on_conflict: :discard
    retry_on StandardError, wait: 30.seconds, attempts: 3

    def perform(tenant_id, base_url)
      tenant = Tenant.active.find_by(id: tenant_id)
      return unless tenant && tenant.public_base_url(fallback_base_url: base_url) == base_url

      Current.set(tenant: tenant) do
        SitemapCache.refresh!(tenant: tenant, base_url: base_url)
      end
    end
  end
end
