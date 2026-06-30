require 'rails_helper'

RSpec.describe CheckIns::StaleActiveCheckinJob do
  before { Setting.set("field_checkin_enabled", "true") }

  let(:user) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }

  it "fecha check-ins ativos sem ping há mais de 10min" do
    old = create(:check_in, admin_user: user, store: store, status: :active, checked_in_at: 30.minutes.ago)
    described_class.new.perform
    expect(old.reload.closed_auto_out_of_radius?).to be true
  end

  it "NÃO fecha check-ins com ping recente" do
    fresh = create(:check_in, admin_user: user, store: store, status: :active, checked_in_at: 30.minutes.ago)
    create(:location_ping, check_in: fresh, admin_user: user, recorded_at: 2.minutes.ago)
    described_class.new.perform
    expect(fresh.reload.active?).to be true
  end

  it "não faz nada com flag desligada" do
    Setting.set("field_checkin_enabled", "false")
    old = create(:check_in, admin_user: user, store: store, status: :active, checked_in_at: 30.minutes.ago)
    described_class.new.perform
    expect(old.reload.active?).to be true
  end

  it "quando recebe tenant_id fecha apenas check-ins daquele tenant" do
    current_tenant = Tenant.create!(name: "Tenant stale #{SecureRandom.hex(3)}", slug: "tenant-stale-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro stale #{SecureRandom.hex(3)}", slug: "outro-stale-#{SecureRandom.hex(3)}")
    current_user = create(:admin_user, :field_agent, tenant: current_tenant)
    other_user = create(:admin_user, :field_agent, tenant: other_tenant)
    current_store = create(:store, tenant: current_tenant)
    other_store = create(:store, tenant: other_tenant)
    current_check_in = create(:check_in, tenant: current_tenant, admin_user: current_user, store: current_store, status: :active, checked_in_at: 30.minutes.ago)
    other_check_in = create(:check_in, tenant: other_tenant, admin_user: other_user, store: other_store, status: :active, checked_in_at: 30.minutes.ago)

    described_class.new.perform(tenant_id: current_tenant.id)

    expect(current_check_in.reload.closed_auto_out_of_radius?).to be true
    expect(other_check_in.reload.active?).to be true
  end
end
