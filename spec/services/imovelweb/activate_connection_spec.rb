require "rails_helper"

RSpec.describe Imovelweb::ActivateConnection do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:connection) { ImovelwebConnection.create!(tenant: tenant, environment: "production", client_code: "47294717", advertiser_code: "47294717", authorization_requested_at: Time.current) }
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("IMOVELWEB_RECEIVING_ENABLED").and_return("true")
    allow(connection).to receive(:encryption_ready?).and_return(true)
    allow(Imovelweb::GatewayClient).to receive(:verify!).with(connection).and_return({"confirmed"=>true,"advertiser_code"=>"47294717"})
    allow(Imovelweb::GatewayClient).to receive(:sync!).with(connection).and_return(true)
  end

  it "confirms the exact authorized branch and synchronizes once without changing publication or rules" do
    publication = PortalIntegration.for_portal!("imovelweb", tenant: tenant)
    previous = publication.attributes
    expect(described_class.call(connection)).to be(true)
    expect(connection.reload).to have_attributes(enabled: true, advertiser_code: "47294717", connection_error: nil)
    expect(connection.authorized_at).to be_present
    expect(connection.gateway_synced_at).to be_present
    connection.update!(connection_error: "Falha transitória")
    expect(described_class.call(connection)).to be(true)
    expect(connection.reload.connection_error).to be_nil
    expect(Imovelweb::GatewayClient).to have_received(:sync!).once
    expect(publication.reload.attributes).to eq(previous)
  end

  it "does not activate before provider consent" do
    allow(Imovelweb::GatewayClient).to receive(:verify!).and_return({"confirmed"=>false})
    expect(described_class.call(connection)).to be(false)
    expect(connection.reload).to have_attributes(enabled: false, authorized_at: nil, gateway_synced_at: nil)
    expect(Imovelweb::GatewayClient).not_to have_received(:sync!)
  end

  it "rejects an authorization for another branch" do
    allow(Imovelweb::GatewayClient).to receive(:verify!).and_return({"confirmed"=>true,"advertiser_code"=>"other-branch"})
    expect { described_class.call(connection) }.to raise_error(Imovelweb::GatewayClient::Error, /sucursal/)
    expect(connection.reload.enabled).to be(false)
    expect(Imovelweb::GatewayClient).not_to have_received(:sync!)
  end

  it "rolls back activation if the gateway refuses the route and succeeds on retry" do
    allow(Imovelweb::GatewayClient).to receive(:sync!).and_raise(Imovelweb::GatewayClient::Error, "offline")
    expect { described_class.call(connection) }.to raise_error(Imovelweb::GatewayClient::Error)
    expect(connection.reload).to have_attributes(enabled: false, authorized_at: nil, gateway_synced_at: nil)
    allow(Imovelweb::GatewayClient).to receive(:sync!).and_return(true)
    expect(described_class.call(connection)).to be(true)
  end

  it "preserves an already active legacy connection if verification fails" do
    connection.update!(authorized_at: 1.day.ago, enabled: true, authorization_requested_at: nil)
    allow(Imovelweb::GatewayClient).to receive(:verify!).and_raise(Imovelweb::GatewayClient::Error, "offline")
    expect { described_class.call(connection) }.to raise_error(Imovelweb::GatewayClient::Error)
    expect(connection.reload).to have_attributes(enabled: true)
    expect(connection.authorized_at).to be_present
  end

  it "normalizes only empty legacy drafts, without changing records with history" do
    connection.update_column(:client_code, "um-#{SecureRandom.uuid}")
    allow(Imovelweb::GatewayClient).to receive(:verify!).and_return({"confirmed"=>false})
    expect(described_class.call(connection)).to be(false)
    expect(connection.reload.client_code).to eq("47294717")
    connection.update_column(:client_code, "um-#{SecureRandom.uuid}")
    connection.imovelweb_lead_receipts.create!(event_id: "historic", event_type: "CONTACTO", payload: "{}", received_at: Time.current)
    original=connection.client_code
    expect { described_class.call(connection) }.to raise_error(Imovelweb::GatewayClient::Error, /histórico/)
    expect(connection.reload.client_code).to eq(original)
  end

  it "requires ownership confirmation for a new native account and preserves the global gate" do
    allow(Imovelweb::GatewayClient).to receive(:verify!).and_return({"confirmed"=>false,"ownership_required"=>true,"advertiser_code"=>"47294717","email_hint"=>"o***@example.com"})
    expect(described_class.call(connection)).to be(false)
    expect(connection.reload.consent_confirmed_at).to be_present
    expect(connection.enabled).to be(false)
    allow(Imovelweb::GatewayClient).to receive(:verify!).and_return({"confirmed"=>true,"advertiser_code"=>"47294717"})
    allow(ENV).to receive(:[]).with("IMOVELWEB_RECEIVING_ENABLED").and_return("false")
    expect { described_class.call(connection) }.to raise_error(Imovelweb::GatewayClient::Error, /indisponível/)
    expect(connection.reload.enabled).to be(false)
  end
end
