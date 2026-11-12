require "rails_helper"
require_relative "../../support/sitemap_snapshots"

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

  let(:tenant) { Tenant.default }
  let(:base_url) { "https://example.test" }

  include_context "isolated sitemap snapshots"

  it "queues a cold snapshot without generating anything in the request" do
    expect(Seo::SitemapBuilder).not_to receive(:new)
    expect(Seo::SitemapRefreshJob).to receive(:perform_later).with(tenant.id, base_url)
    expect(described_class.fetch(tenant: tenant, base_url: base_url)).to be_nil
  end

  it "serves the last valid snapshot immediately while it is being rebuilt" do
    builder = instance_double(Seo::SitemapBuilder, to_xml: "<urlset/>")
    allow(Seo::SitemapBuilder).to receive(:new).and_return(builder)
    described_class.refresh!(tenant: tenant, base_url: base_url)
    expect(Seo::SitemapBuilder).not_to receive(:new)
    expect(Seo::SitemapRefreshJob).to receive(:perform_later).with(tenant.id, base_url)

    File.open(Rails.root.join("tmp", "sitemap-#{tenant.id}.lock"), "a") do |lock|
      lock.flock(File::LOCK_EX)
      travel 31.minutes do
        reader = Thread.new { described_class.fetch(tenant: tenant, base_url: base_url) }
        begin
          expect(reader.join(1)).to eq(reader)
          expect(reader.value).to eq("<urlset/>")
        ensure
          lock.flock(File::LOCK_UN)
          reader.join
        end
      end
    end
  end

  it "keeps the last good version if rebuilding fails and retries after that" do
    builder = instance_double(Seo::SitemapBuilder, to_xml: "<old/>")
    allow(Seo::SitemapBuilder).to receive(:new).and_return(builder)
    described_class.refresh!(tenant: tenant, base_url: base_url)
    travel 31.minutes do
      allow(builder).to receive(:to_xml).and_raise(IOError, "failed")
      expect { described_class.refresh!(tenant: tenant, base_url: base_url) }.to raise_error(IOError)
      expect(described_class.fetch(tenant: tenant, base_url: base_url)).to eq("<old/>")
      allow(builder).to receive(:to_xml).and_return("<new/>")
      described_class.refresh!(tenant: tenant, base_url: base_url)
      expect(described_class.fetch(tenant: tenant, base_url: base_url)).to eq("<new/>")
    end
  end

  it "preserves the snapshot through Redis eviction and an enqueue failure" do
    allow(Seo::SitemapBuilder).to receive(:new).and_return(instance_double(Seo::SitemapBuilder, to_xml: "<urlset/>"))
    described_class.refresh!(tenant: tenant, base_url: base_url)
    cache.clear
    expect(described_class.fetch(tenant: tenant, base_url: base_url)).to eq("<urlset/>")
    travel 31.minutes do
      allow(Seo::SitemapRefreshJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue unavailable")
      expect(Rails.error).to receive(:report).with(instance_of(ActiveJob::EnqueueError), hash_including(handled: true))
      expect(described_class.fetch(tenant: tenant, base_url: base_url)).to eq("<urlset/>")
    end
  end

  it "keeps snapshots separate by account and domain" do
    other = Tenant.create!(name: "Other snapshot", slug: "other-snapshot")
    allow(Seo::SitemapBuilder).to receive(:new).and_return(instance_double(Seo::SitemapBuilder, to_xml: "<one/>"))
    described_class.refresh!(tenant: tenant, base_url: base_url)
    expect(described_class.fetch(tenant: other, base_url: base_url)).to be_nil
    expect(described_class.fetch(tenant: tenant, base_url: "https://other.test")).to be_nil
    expect(described_class.fetch(tenant: tenant, base_url: base_url)).to eq("<one/>")
  end
end
