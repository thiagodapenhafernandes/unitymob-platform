require "rails_helper"

RSpec.describe Vista::BackfillBrokersService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "vincula corretores apenas aos imóveis do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant backfill #{SecureRandom.hex(3)}", slug: "tenant-backfill-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro backfill #{SecureRandom.hex(3)}", slug: "outro-backfill-#{SecureRandom.hex(3)}")
    current_profile = current_tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    broker = create(:admin_user, tenant: current_tenant, profile: current_profile, vista_id: "BACKFILL-1")
    other_broker = create(:admin_user, tenant: other_tenant, profile: other_profile, vista_id: "BACKFILL-1")
    current_habitation = create(:habitation, tenant: current_tenant, codigo: "IMO-1", admin_user: nil)
    other_habitation = create(:habitation, tenant: other_tenant, codigo: "IMO-2", admin_user: nil)

    Current.tenant = current_tenant
    service = described_class.new
    allow(service).to receive(:fetch).with(1).and_return(
      {
        "paginas" => 1,
        "pagina" => 1,
        "total" => 1,
        "quantidade" => 1,
        "1" => { "Codigo" => "IMO-1", "CodigoCorretor" => "BACKFILL-1" }
      }
    )

    service.call

    expect(current_habitation.reload.admin_user).to eq(broker)
    expect(other_habitation.reload.admin_user).to be_nil
    expect(other_broker.reload.vista_id).to eq("BACKFILL-1")
  end
end
