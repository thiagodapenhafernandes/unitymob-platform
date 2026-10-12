require "rails_helper"

RSpec.describe Leads::InternalContactScope do
  it "preserva seleção e exclusão por telefone principal e secundário dentro da conta" do
    tenant = create(:admin_user, phone: "47984895559", secondary_phone: "47988887777").tenant
    first = create(:lead, tenant: tenant, phone: "5547984895559")
    second = create(:lead, tenant: tenant, phone: "5547999991111")
    second.update_columns(client_phone: "(55) 47 98888-7777")
    customer = create(:lead, tenant: tenant, phone: "5547999992222")
    other = Tenant.create!(name: "Outra", slug: "internal-scope-#{SecureRandom.hex(4)}")
    foreign = create(:lead, tenant: other, phone: first.phone)
    query = described_class.new(tenant: tenant)
    expect(query.matching.pluck(:id)).to match_array([first.id, second.id])
    expect(query.exclude(Lead.where(id: [first.id, second.id, customer.id, foreign.id])).pluck(:id)).to eq([customer.id])
    empty = described_class.new(tenant: other)
    expect(empty.matching).to be_empty
    expect(empty.exclude(other.leads).pluck(:id)).to eq([foreign.id])
  end

  it "exige uma conta persistida" do
    expect { described_class.new(tenant: nil) }.to raise_error(ArgumentError)
  end
end
