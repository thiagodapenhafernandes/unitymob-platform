require "rails_helper"

RSpec.describe Seo::SitemapCache do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it "builds a cold sitemap once when workers request the same key concurrently" do
    ready = Queue.new
    start = Queue.new
    builds = Queue.new
    threads = 3.times.map do
      Thread.new do
        ready << true
        start.pop
        described_class.fetch(tenant_id: 1, key: "sitemap-concurrent") do
          builds << true
          sleep 0.03
          "<urlset/>"
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
