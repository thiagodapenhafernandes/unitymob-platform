module Seo
  class SitemapCache
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
