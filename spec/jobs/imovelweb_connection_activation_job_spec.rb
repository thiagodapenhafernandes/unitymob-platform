require "rails_helper"

RSpec.describe ImovelwebConnectionActivationJob, type: :job do
  let(:connection) { ImovelwebConnection.create!(tenant: create(:admin_user, :admin).tenant, environment: "production", client_code: "um-#{SecureRandom.uuid}", authorization_requested_at: Time.current) }
  before { allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) }

  it "rechecks pending consent without activating anything and broadcasts only to its connection" do
    allow(Imovelweb::ActivateConnection).to receive(:call).with(connection).and_return(false)
    expect { described_class.perform_now(connection.id) }.to have_enqueued_job(described_class).with(connection.id)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(connection, :connection_status, hash_including(target: "imovelweb_connection_status_#{connection.id}"))
    expect(connection.reload.enabled).to be(false)
  end

  it "stops when confirmed or the authorization window expires" do
    allow(Imovelweb::ActivateConnection).to receive(:call).and_return(true)
    expect { described_class.perform_now(connection.id) }.not_to have_enqueued_job(described_class)
    connection.update!(authorization_requested_at: 16.minutes.ago)
    described_class.perform_now(connection.id)
    expect(Imovelweb::ActivateConnection).to have_received(:call).once
  end

  it "does not process sandbox connections or records without a self-service request" do
    allow(Imovelweb::ActivateConnection).to receive(:call)
    connection.update_column(:authorization_requested_at, nil)
    described_class.perform_now(connection.id)
    connection.update_columns(authorization_requested_at: Time.current, environment: "sandbox")
    described_class.perform_now(connection.id)
    expect(Imovelweb::ActivateConnection).not_to have_received(:call)
  end
end
