require 'rails_helper'

RSpec.describe AntiFraud::AnalyzePingJob do
  let(:user) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }
  let(:check_in) { create(:check_in, admin_user: user, store: store, status: :active) }

  it "flagga ping + check_in + audit log quando analyzer acusa suspeito" do
    ping = create(:location_ping,
                  check_in: check_in,
                  admin_user: user,
                  latitude: -26.9906,
                  longitude: -48.6348,
                  recorded_at: Time.current,
                  is_mock_location: true)

    expect {
      described_class.new.perform(ping.id)
    }.to change { CheckinAuditLog.where(action: "flagged_suspicious").count }.by(1)

    expect(ping.reload.suspicious).to be true
    expect(ping.suspicious_reasons).to include("mock_location")

    expect(check_in.reload.suspicious).to be true
    expect(check_in.suspicious_reasons).to include("mock_location")
  end

  it "não faz nada quando ping é limpo" do
    ping = create(:location_ping,
                  check_in: check_in,
                  admin_user: user,
                  latitude: -26.9906,
                  longitude: -48.6348,
                  recorded_at: Time.current,
                  is_mock_location: false)

    expect {
      described_class.new.perform(ping.id)
    }.not_to change { CheckinAuditLog.count }

    expect(ping.reload.suspicious).to be false
  end
end
