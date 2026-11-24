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

  it "restores database timeouts after recording an event" do
    connection = ActiveRecord::Base.connection
    before_timeouts = connection.select_one("SELECT current_setting('statement_timeout'), current_setting('lock_timeout')")
    event = described_class.call(tenant:, admin_user:, request:, event_name: "property_opened")

    expect(event).to be_persisted
    expect(connection.select_one("SELECT current_setting('statement_timeout'), current_setting('lock_timeout')")).to eq(before_timeouts)
  end

  it "rolls back the tracking operation on a real database timeout and keeps the connection usable" do
    admin_user
    tracker = described_class.new(tenant:, admin_user:, request:, event_name: "property_opened")
    connection = ActiveRecord::Base.connection
    before_timeouts = connection.select_one("SELECT current_setting('statement_timeout'), current_setting('lock_timeout')")
    allow(tracker).to receive(:current_or_new_session).and_wrap_original do |original, now|
      activity_session = original.call(now)
      connection.execute("SELECT pg_sleep(0.7)")
      activity_session
    end

    expect { expect(tracker.call).to be_nil }.not_to change(OperationalUserSession, :count)
    expect(OperationalUserEvent.count).to eq(0)
    expect(request_session[:operational_user_session_id]).to be_nil
    expect(connection.select_one("SELECT current_setting('statement_timeout'), current_setting('lock_timeout')")).to eq(before_timeouts)
    expect(connection.select_value("SELECT 1")).to eq(1)
  end

  it "does not reuse another tenant's operational session" do
    foreign_tenant = Tenant.create!(name: "Other activity tenant", slug: "other-activity-#{SecureRandom.hex(4)}")
    foreign_admin = create(:admin_user, :admin, tenant: foreign_tenant)
    foreign_session = OperationalUserSession.create!(tenant: foreign_tenant, admin_user: foreign_admin)
    request_session[:operational_user_session_id] = foreign_session.id

    event = described_class.call(tenant:, admin_user:, request:, event_name: "property_opened")

    expect(event.tenant_id).to eq(tenant.id)
    expect(event.operational_user_session_id).not_to eq(foreign_session.id)
    expect(foreign_session.reload.events_count).to eq(0)
  end

  it "rolls back an inserted event when updating its existing session fails" do
    previous_event = described_class.call(tenant:, admin_user:, request:, event_name: "property_list_viewed")
    activity_session = previous_event.operational_user_session
    previous_session_id = request_session[:operational_user_session_id]
    tracker = described_class.new(tenant:, admin_user:, request:, event_name: "property_opened")
    allow(tracker).to receive(:current_or_new_session).and_return(activity_session)
    allow(activity_session).to receive(:record_event!).and_raise(ActiveRecord::LockWaitTimeout)

    expect { expect(tracker.call).to be_nil }.not_to change(OperationalUserEvent, :count)
    expect(request_session[:operational_user_session_id]).to eq(previous_session_id)
    expect(activity_session.reload.events_count).to eq(1)
  end
end
