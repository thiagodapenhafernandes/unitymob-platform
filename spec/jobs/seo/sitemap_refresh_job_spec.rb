require "rails_helper"

RSpec.describe Seo::SitemapRefreshJob, type: :job do
  let(:tenant) { Tenant.default }
  let(:base_url) { "https://example.test" }

  it "generates under the account context on a queue separate from C2S" do
    expect(Seo::SitemapCache).to receive(:refresh!).with(tenant: tenant, base_url: base_url) do
      expect(Current.tenant).to eq(tenant)
    end
    described_class.perform_now(tenant.id, base_url)
    expect(described_class.queue_name).to eq("default")
  end

  it "does not generate for inactive accounts or a replaced canonical domain" do
    tenant.update!(active: false)
    expect(Seo::SitemapCache).not_to receive(:refresh!)
    described_class.perform_now(tenant.id, base_url)
    tenant.update!(active: true)
    tenant.tenant_domains.create!(hostname: "current.test", primary_domain: true)
    described_class.perform_now(tenant.id, base_url)
  end

  it "deduplicates queued and running refreshes for one account and domain" do
    first = described_class.new(tenant.id, base_url)
    expect(first.concurrency_key).to eq(described_class.new(tenant.id, base_url).concurrency_key)
    expect(first.concurrency_key).not_to eq(described_class.new(tenant.id + 1, base_url).concurrency_key)
    expect(first.concurrency_key).not_to eq(described_class.new(tenant.id, "https://other.test").concurrency_key)
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_on_conflict).to eq(:discard)
  end

  it "discards duplicate queue records without discarding another account" do
    SolidQueue::Job.transaction(requires_new: true) do
      first = described_class.new(tenant.id, base_url)
      duplicate = described_class.new(tenant.id, base_url)
      other = described_class.new(tenant.id + 1, base_url)
      [first, duplicate, other].each { |job| SolidQueue::Job.enqueue(job) }
      expect(first).to be_successfully_enqueued
      expect(duplicate).not_to be_successfully_enqueued
      expect(other).to be_successfully_enqueued
      raise ActiveRecord::Rollback
    end
  end

  it "schedules a bounded retry if generation fails" do
    allow(Seo::SitemapCache).to receive(:refresh!).and_raise(IOError, "write failed")
    expect { described_class.perform_now(tenant.id, base_url) }
      .to have_enqueued_job(described_class).with(tenant.id, base_url).at(a_value_within(5.seconds).of(30.seconds.from_now))
  end
end
