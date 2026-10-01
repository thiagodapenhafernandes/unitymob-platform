require "rails_helper"

RSpec.describe Habitation, "cache público da home" do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  it "invalida o contador de imóveis do hero ao limpar o cache da home da conta" do
    store.write("hero_listing_count:tenant:7", 10)
    store.write("hero_listing_count:tenant:8", 20)

    described_class.clear_public_home_cache_for_tenant(7)

    expect(store.read("hero_listing_count:tenant:7")).to be_nil
    expect(store.read("hero_listing_count:tenant:8")).to eq(20)
  end

  it "invalida o contador do hero quando um imóvel da conta é salvo" do
    tenant = Tenant.default
    property = create(:habitation, tenant:, exibir_no_site_flag: true)
    store.write("hero_listing_count:tenant:#{tenant.id}", 10)

    property.update!(valor_venda_cents: property.valor_venda_cents.to_i + 100)

    expect(store.read("hero_listing_count:tenant:#{tenant.id}")).to be_nil
  end
end
