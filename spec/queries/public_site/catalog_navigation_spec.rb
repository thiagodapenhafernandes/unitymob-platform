require "rails_helper"

RSpec.describe PublicSite::CatalogNavigation do
  let(:tenant) { Tenant.default }

  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  def total_count = described_class.call(tenant:).first&.dig(:count).to_i

  it "mantém o catálogo aquecido quando apenas a publicação de imagens renova o HTML" do
    create(:habitation, tenant:, exibir_no_site_flag: true)
    before_count = total_count
    expect_any_instance_of(described_class).not_to receive(:build_groups)
    PublicSite::PageVersion.bump(tenant.id)
    expect(total_count).to eq(before_count)
  end

  it "reflete na hora um imóvel excluído, mesmo sendo o mais antigo (maior updated_at não muda)" do
    older = create(:habitation, tenant:, exibir_no_site_flag: true)
    create(:habitation, tenant:, exibir_no_site_flag: true)
    before_count = total_count

    older.destroy!

    expect(total_count).to eq(before_count - 1)
  end

  it "reflete na hora um imóvel salvo" do
    property = create(:habitation, tenant:, exibir_no_site_flag: true)
    expect(total_count).to be >= 1

    property.update!(exibir_no_site_flag: false)

    expect(total_count).to eq(0)
  end

  it "preserva filtros e contagens quando muda apenas o estado da sincronização" do
    property = create(:habitation, tenant:, exibir_no_site_flag: true)
    total_count
    filter_key = Habitation.public_filter_location_options_cache_key(tenant.id)
    Rails.cache.write(filter_key, ["cache aquecido"])
    expect_any_instance_of(described_class).not_to receive(:build_groups)

    property.update!(last_sync_at: Time.current, last_sync_status: "success", last_sync_message: "Sincronizado")

    expect(Rails.cache.read(filter_key)).to eq(["cache aquecido"])
    expect(total_count).to be >= 1
  end

  it "renova filtros e contagens quando a sincronização também muda o imóvel" do
    property = create(:habitation, tenant:, exibir_no_site_flag: true)
    total_count
    filter_key = Habitation.public_filter_location_options_cache_key(tenant.id)
    Rails.cache.write(filter_key, ["cache aquecido"])

    property.update!(last_sync_at: Time.current, exibir_no_site_flag: false)

    expect(Rails.cache.read(filter_key)).to be_nil
    expect(total_count).to eq(0)
  end
end
