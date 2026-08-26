require "rails_helper"

RSpec.describe ExternalLeadMigration::IncrementalSyncJob, type: :job do
  let(:tenant) { Tenant.default }
  let(:integration) do
    create(
      :external_lead_integration,
      tenant: tenant,
      last_error_message: "ExternalLeadMigration::Client::Error: Internal Server Error",
      last_cursor_at: Time.zone.parse("2026-08-20 10:00:00")
    )
  end
  let(:client) { instance_double(ExternalLeadMigration::Client) }

  before do
    allow(ExternalLeadMigration::Client).to receive(:new).with(token: integration.access_token).and_return(client)
    allow(client).to receive(:leads).and_return({ "data" => [], "meta" => { "total" => 0 } })
  end

  it "limpa o ultimo erro quando a sincronizacao incremental conclui" do
    described_class.perform_now(integration.id)

    expect(integration.reload).to have_attributes(
      sync_status: "completed",
      last_error_message: nil
    )
  end

  it "permite ressincronizar uma janela antiga sem alterar o token" do
    described_class.perform_now(integration.id, "2026-08-12T00:00:00Z")

    expect(client).to have_received(:leads).with(
      page: 1,
      perpage: described_class::PER_PAGE,
      params: { sort: "-updated_at", updated_gte: "2026-08-12T00:00:00Z" }
    )
  end
end
