require "rails_helper"

RSpec.describe Vista::OperationalImportService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  def build_batch
    VistaImportBatch.create!(dump_dir: "spec", status: "completed")
  end

  it "carrega referencias operacionais apenas do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant op #{SecureRandom.hex(3)}", slug: "tenant-op-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro op #{SecureRandom.hex(3)}", slug: "outro-op-#{SecureRandom.hex(3)}")
    current_profile = current_tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    current_user = create(:admin_user, tenant: current_tenant, profile: current_profile, vista_id: "OP-USER-1")
    create(:admin_user, tenant: other_tenant, profile: other_profile, vista_id: "OP-USER-2")
    current_proprietor = create(:proprietor, tenant: current_tenant, vista_code: "OP-PROP-1")
    create(:proprietor, tenant: other_tenant, vista_code: "OP-PROP-2")
    current_habitation = create(:habitation, tenant: current_tenant, codigo: "OP-HAB-1")
    create(:habitation, tenant: other_tenant, codigo: "OP-HAB-2")

    Current.tenant = current_tenant
    service = described_class.new(batch: build_batch, dry_run: true)
    service.send(:load_reference_ids)

    expect(service.instance_variable_get(:@admin_user_id_by_code)).to eq("OP-USER-1" => current_user.id)
    expect(service.instance_variable_get(:@proprietor_id_by_code)).to eq("OP-PROP-1" => current_proprietor.id)
    expect(service.instance_variable_get(:@habitation_id_by_code)).to eq("OP-HAB-1" => current_habitation.id)
  end
end
