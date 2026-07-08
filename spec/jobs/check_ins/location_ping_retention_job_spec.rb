require "rails_helper"

RSpec.describe CheckIns::LocationPingRetentionJob do
  let(:user) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }
  let(:check_in) { create(:check_in, admin_user: user, store: store, status: :active) }

  it "apaga pings anteriores ao período de retenção e mantém os recentes" do
    old_ping = create(:location_ping, check_in: check_in, admin_user: user, recorded_at: 100.days.ago)
    fresh_ping = create(:location_ping, check_in: check_in, admin_user: user, recorded_at: 10.days.ago)

    deleted = described_class.new.perform

    expect(deleted).to eq(1)
    expect(LocationPing.exists?(old_ping.id)).to be false
    expect(LocationPing.exists?(fresh_ping.id)).to be true
  end

  it "respeita o parâmetro older_than customizado" do
    ping = create(:location_ping, check_in: check_in, admin_user: user, recorded_at: 40.days.ago)

    described_class.new.perform(older_than: 30.days.ago)

    expect(LocationPing.exists?(ping.id)).to be false
  end

  it "apaga em múltiplos lotes quando o volume excede o batch_size" do
    3.times { create(:location_ping, check_in: check_in, admin_user: user, recorded_at: 100.days.ago) }

    deleted = described_class.new.perform(batch_size: 1)

    expect(deleted).to eq(3)
    expect(LocationPing.where(check_in_id: check_in.id).count).to eq(0)
  end

  it "é no-op tolerante quando a tabela não existe" do
    allow(LocationPing).to receive(:table_exists?).and_return(false)

    expect(described_class.new.perform).to eq(0)
  end
end
