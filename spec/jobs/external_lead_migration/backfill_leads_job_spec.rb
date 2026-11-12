require "rails_helper"

RSpec.describe ExternalLeadMigration::BackfillLeadsJob do
  it "conta cadastros filtrados sem tratá-los como importados ou falhas" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    integration = create(:external_lead_integration, tenant: tenant, mirror_c2s_owners: true,
      incoming_business_type: "sale", seller_mappings: { "seller" => broker.id })
    rows = ["Venda", "Locação"].each_with_index.map do |kind, index|
      { "id" => "filtered-history-#{index}", "attributes" => {
        "customer" => { "name" => "Cliente #{index}", "phone" => "554799999123#{index}" },
        "seller" => { "id" => "seller", "name" => broker.name, "email" => broker.email },
        "product" => { "negotiation_name" => kind },
        "lead_status" => { "alias" => "new" }
      } }
    end
    client = instance_double(ExternalLeadMigration::Client)
    allow(ExternalLeadMigration::Client).to receive(:new).and_return(client)
    allow(client).to receive(:leads).and_return({ "data" => rows, "meta" => { "total" => 2 } })
    described_class.new.perform(integration.id)
    expect(integration.reload).to have_attributes(imported_count: 1, updated_count: 0, failed_count: 0, filtered_count: 1, sync_status: "completed")
    expect(integration).to be_mirror_c2s_owners
    expect(integration.incoming_business_type).to eq("sale")
    expect(integration.leads.pluck(:external_lead_id)).to eq(["filtered-history-0"])
  end
end
