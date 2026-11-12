module Seo
  class SitemapCache
    def self.key(tenant:, base_url:)
      # A SQL de publicly_visible inclui Time.current; seu cache_key muda a cada request.
      count, updated_at = tenant.blog_articles.publicly_visible.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
      [Habitation.public_sitemap_cache_key(tenant.id, base_url), count, updated_at&.utc&.strftime("%s%6N"), tenant.blog_categories.cache_key_with_version]
    end

    def self.fetch(tenant_id:, key:, &block)
      cached = Rails.cache.read(key)
      return cached if cached

      # shortcut: o lock cobre os workers deste host; usar lock distribuído se a conta tiver vários hosts.
      File.open(Rails.root.join("tmp", "sitemap-#{Integer(tenant_id)}.lock"), "a", 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        Rails.cache.fetch(key, expires_in: 30.minutes, &block)
      end
    end
  end
end
