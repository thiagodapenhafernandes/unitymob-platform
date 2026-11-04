require "rails_helper"

RSpec.describe ExternalLeadMigration::OwnerAudit do
  let(:tenant) { Tenant.default }
  let(:integration) { create(:external_lead_integration, tenant: tenant) }

  it "mostra divergência, primeiro recebimento e aceite sem reatribuir nem incluir outra conta" do
    original = create(:admin_user, tenant: tenant)
    current = create(:admin_user, tenant: tenant)
    lead = create(:lead, tenant: tenant, admin_user: current, external_lead_integration: integration,
      skip_automatic_routing: true, other_information: { "external_lead_seller" => { "name" => original.name, "email" => original.email } })
    lead.activities.create!(tenant: tenant, kind: "distributed", metadata: { admin_user_name: original.name })
    lead.activities.create!(tenant: tenant, kind: "accepted", metadata: { by: current.name })
    create(:lead, tenant: Tenant.create!(name: "Outra conta", slug: "outra-#{SecureRandom.hex(4)}"), skip_automatic_routing: true, other_information: { source: "external_lead_migration" })

    rows = described_class.new(integration: integration).each_difference.to_a
    expect(rows.size).to eq(1)
    expect(rows.first).to include(lead_id: lead.id, local_owner: current.name, external_owner: original.name,
      first_received_by: original.name, local_acceptance: true, operational_assignment: true)
    expect(lead.reload.admin_user).to eq(current)
  end
end
