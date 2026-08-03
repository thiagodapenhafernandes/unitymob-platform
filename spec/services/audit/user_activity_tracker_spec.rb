require "rails_helper"

RSpec.describe Audit::UserActivityTracker do
  let(:tenant) { Tenant.default }
  let(:admin_user) { create(:admin_user, :admin, tenant:) }
  let(:request_session) { {} }
  let(:request) do
    double(
      "request",
      session: request_session,
      fullpath: "/admin/habitations?codigo=8040&telefone=47999990000",
      request_method: "GET",
      user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile Safari/604.1",
      remote_ip: "127.0.0.1"
    )
  end

  before do
    Current.tenant = tenant
  end

  it "creates an operational session and redacts sensitive filter values" do
    event = described_class.call(
      tenant:,
      admin_user:,
      request:,
      event_name: "catalog_search",
      query_text: "Epic Tower",
      result_count: 50,
      visible_habitation_ids: [1, "2", "x", 1],
      filter_params: {
        codigo: "8040",
        telefone: "47999990000",
        owner: { email: "cliente@example.test", cidade: "Curitiba" }
      }
    )

    expect(event).to be_persisted
    expect(event.operational_user_session).to be_persisted
    expect(event.name).to eq("catalog_search")
    expect(event.query_text).to eq("Epic Tower")
    expect(event.result_count).to eq(50)
    expect(event.visible_habitation_ids).to eq([1, 2])
    expect(event.filter_params).to include("codigo" => "8040", "telefone" => "[redigido]")
    expect(event.filter_params.dig("owner", "email")).to eq("[redigido]")
    expect(event.filter_params.dig("owner", "cidade")).to eq("Curitiba")
    expect(event.operational_user_session.events_count).to eq(1)
  end

  it "reuses the same operational session while it is active" do
    first_event = described_class.call(tenant:, admin_user:, request:, event_name: "property_list_viewed")
    second_event = described_class.call(tenant:, admin_user:, request:, event_name: "property_opened")

    expect(second_event.operational_user_session).to eq(first_event.operational_user_session)
    expect(OperationalUserSession.count).to eq(1)
    expect(first_event.operational_user_session.reload.events_count).to eq(2)
  end

  it "ignores unknown event names" do
    expect {
      described_class.call(tenant:, admin_user:, request:, event_name: "unknown")
    }.not_to change(OperationalUserEvent, :count)
  end
end
