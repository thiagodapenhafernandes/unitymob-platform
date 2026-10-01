require "rails_helper"

RSpec.describe PublicSite::CatalogNavigation do
  let(:tenant) { Tenant.default }

  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  def total_count = described_class.call(tenant:).first&.dig(:count).to_i

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
end
