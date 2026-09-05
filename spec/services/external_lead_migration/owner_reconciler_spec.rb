require "rails_helper"

RSpec.describe ExternalLeadMigration::OwnerReconciler do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant:, name: "Adriana Stark", email: "adriana.local@example.test", vista_id: "108") }
  let(:integration) { create(:external_lead_integration, tenant:, seller_mappings: {}) }

  before do
    Current.tenant = tenant
    broker
  end

  it "faz dry-run dos leads C2S sem corretor que podem ser atribuídos pelo seller externo" do
    lead = create_c2s_lead(status: Lead.status_value(:novo))

    result = described_class.call(integration:)

    expect(result).to have_attributes(scanned: 1, assigned: 1, unmapped: 0)
    expect(lead.reload.admin_user).to be_nil
  end

  it "atribui o corretor local quando EXECUTE esta ativo" do
    lead = create_c2s_lead(status: Lead.status_value(:novo))

    result = described_class.call(integration:, execute: true)

    expect(result).to have_attributes(scanned: 1, assigned: 1, unmapped: 0)
    expect(lead.reload.admin_user).to eq(broker)
  end

  it "permite restringir o backfill a leads operacionais" do
    create_c2s_lead(status: Lead.status_value(:descartado))

    result = described_class.call(integration:, execute: true, operational_only: true)

    expect(result).to have_attributes(scanned: 1, assigned: 0, skipped_non_operational: 1)
  end

  def create_c2s_lead(status:)
    create(
      :lead,
      tenant: tenant,
      external_lead_integration: integration,
      external_lead_id: SecureRandom.hex(8),
      origin: ExternalLeadIntegration::LEAD_ORIGIN,
      status: status,
      admin_user: nil,
      agent_name: "Adriana Stark",
      agent_email: "adriana.stark@saluteimoveis.com",
      agent_external_id: "9476cd715e6fc5e79a944a88bc71771f",
      other_information: {
        "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
        "external_lead_seller" => {
          "id" => "9476cd715e6fc5e79a944a88bc71771f",
          "name" => "Adriana Stark",
          "email" => "adriana.stark@saluteimoveis.com",
          "external_id" => "108",
          "external_name" => "Adriana Stark"
        }
      }
    )
  end
end
