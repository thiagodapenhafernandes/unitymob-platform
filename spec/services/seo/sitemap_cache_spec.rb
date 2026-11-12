require "rails_helper"

RSpec.describe Seo::SitemapCache do
  include ActiveSupport::Testing::TimeHelpers
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it "keeps the key stable as time passes and changes when content changes or a scheduled article becomes visible" do
    tenant = Tenant.default
    category = tenant.blog_categories.create!(name: "Notícias", slug: "noticias")
    travel_to Time.zone.local(2026, 11, 12, 10) do
      article = tenant.blog_articles.create!(title: "Notícia", content: "Conteúdo", status: "published", blog_categories: [category])
      key = described_class.key(tenant: tenant, base_url: "https://example.test")
      travel 1.second
      expect(described_class.key(tenant: tenant, base_url: "https://example.test")).to eq(key)

      article.update!(excerpt: "Atualizado")
      updated = described_class.key(tenant: tenant, base_url: "https://example.test")
      expect(updated).not_to eq(key)

      tenant.blog_articles.create!(title: "Agendada", content: "Conteúdo", status: "scheduled", published_at: 1.hour.from_now, blog_categories: [category])
      expect(described_class.key(tenant: tenant, base_url: "https://example.test")).to eq(updated)
      travel 1.hour
      expect(described_class.key(tenant: tenant, base_url: "https://example.test")).not_to eq(updated)
    end
  end

  it "builds a cold sitemap once when workers request the same key concurrently" do
    stored = {}
    client = double("Redis")
    allow(client).to receive(:get) { |key| stored[key] }
    allow(client).to receive(:set) { |key, value, **_options| stored[key] = value; "OK" }
    redis_cache = ActiveSupport::Cache::RedisCacheStore.new(redis: client, pool: false)
    allow(Rails).to receive(:cache).and_return(redis_cache)
    ready = Queue.new
    start = Queue.new
    builds = Queue.new
    threads = 3.times.map do
      Thread.new do
        redis_cache.with_local_cache do
          ready << true
          start.pop
          described_class.fetch(tenant_id: 1, key: "sitemap-concurrent") do
            builds << true
            sleep 0.03
            "<urlset/>"
          end
        end
      end
    end
    3.times { ready.pop }
    3.times { start << true }

    expect(threads.map(&:value)).to eq(["<urlset/>"] * 3)
    expect(builds.size).to eq(1)
  end

  it "keeps accounts and cache versions separate and releases the lock after a failed build" do
    expect { described_class.fetch(tenant_id: 1, key: "one/v1") { raise "failed" } }.to raise_error("failed")
    expect(described_class.fetch(tenant_id: 1, key: "one/v1") { "one" }).to eq("one")
    expect(described_class.fetch(tenant_id: 1, key: "one/v1") { raise "cache miss" }).to eq("one")
    expect(described_class.fetch(tenant_id: 1, key: "one/v2") { "updated" }).to eq("updated")
    expect(described_class.fetch(tenant_id: 2, key: "two/v1") { "two" }).to eq("two")
  end
end
