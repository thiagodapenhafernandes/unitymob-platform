module Seo
  class SitemapCache
    MAX_AGE = 30.minutes

    def self.key(tenant:, base_url:)
      # A SQL de publicly_visible inclui Time.current; seu cache_key muda a cada request.
      count, updated_at = tenant.blog_articles.publicly_visible.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
      [Habitation.public_sitemap_cache_key(tenant.id, base_url), count, updated_at&.utc&.strftime("%s%6N"), tenant.blog_categories.cache_key_with_version]
    end

    def self.fetch(tenant:, base_url:)
      snapshot = store.read(snapshot_key(tenant.id, base_url))
      enqueue_refresh(tenant.id, base_url) unless fresh?(snapshot, key(tenant: tenant, base_url: base_url))
      snapshot&.fetch(:xml)
    end

    def self.refresh!(tenant:, base_url:)
      # shortcut: o lock cobre os workers deste host; usar lock distribuído se a conta tiver vários hosts.
      File.open(Rails.root.join("tmp", "sitemap-#{tenant.id}.lock"), "a", 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        version = key(tenant: tenant, base_url: base_url)
        id = snapshot_key(tenant.id, base_url)
        snapshot = store.read(id)
        return snapshot[:xml] if fresh?(snapshot, version)

        xml = Seo::SitemapBuilder.new(base_url: base_url, url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
        raise IOError, "Falha ao publicar sitemap" unless store.write(id, { xml: xml, version: version, generated_at: Time.current })

        xml
      end
    end

    def self.snapshot_key(tenant_id, base_url)
      ["v1", Integer(tenant_id), Digest::SHA256.hexdigest(base_url)]
    end

    def self.store
      # storage é compartilhado entre releases; FileStore publica cada entrada por rename atômico.
      ActiveSupport::Cache::FileStore.new(Rails.root.join("storage/public_sitemaps"))
    end

    def self.fresh?(snapshot, version)
      snapshot && snapshot[:version] == version && snapshot[:generated_at] > MAX_AGE.ago
    end

    def self.enqueue_refresh(tenant_id, base_url)
      Seo::SitemapRefreshJob.perform_later(tenant_id, base_url)
    rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
      Rails.error.report(error, handled: true, context: { tenant_id: tenant_id }, source: "seo.sitemap_refresh")
    end
    private_class_method :store, :fresh?, :enqueue_refresh
  end
end
