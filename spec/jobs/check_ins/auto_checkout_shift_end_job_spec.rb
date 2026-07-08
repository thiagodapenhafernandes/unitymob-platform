require "rails_helper"

RSpec.describe CheckIns::AutoCheckoutShiftEndJob do
  include ActiveSupport::Testing::TimeHelpers

  it "quando recebe tenant_id fecha apenas check-ins daquele tenant" do
    travel_to Time.zone.local(2026, 6, 29, 12, 0, 0) do
      current_tenant = Tenant.create!(name: "Tenant auto checkout #{SecureRandom.hex(3)}", slug: "tenant-auto-checkout-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro auto checkout #{SecureRandom.hex(3)}", slug: "outro-auto-checkout-#{SecureRandom.hex(3)}")
      # Flag POR-TENANT: o job avalia dentro de Current.set(tenant:).
      Setting.set("field_checkin_enabled", "true", tenant: current_tenant)
      Setting.set("field_checkin_enabled", "true", tenant: other_tenant)
      current_user = create(:admin_user, :field_agent, tenant: current_tenant)
      other_user = create(:admin_user, :field_agent, tenant: other_tenant)
      current_store = create(:store, tenant: current_tenant, auto_checkout_after_minutes: 0)
      other_store = create(:store, tenant: other_tenant, auto_checkout_after_minutes: 0)
      current_shift = create(:store_shift, tenant: current_tenant, store: current_store, admin_user: current_user, day_of_week: 1, start_time: "09:00", end_time: "10:00")
      other_shift = create(:store_shift, tenant: other_tenant, store: other_store, admin_user: other_user, day_of_week: 1, start_time: "09:00", end_time: "10:00")
      current_check_in = create(:check_in, tenant: current_tenant, admin_user: current_user, store: current_store, store_shift: current_shift, status: :active, checked_in_at: 3.hours.ago)
      other_check_in = create(:check_in, tenant: other_tenant, admin_user: other_user, store: other_store, store_shift: other_shift, status: :active, checked_in_at: 3.hours.ago)

      described_class.new.perform(tenant_id: current_tenant.id)

      expect(current_check_in.reload.closed_auto_shift_end?).to be true
      expect(other_check_in.reload.active?).to be true
    end
  end

  it "fecha check-in cujo turno terminou ontem à noite e a grace cruzou a meia-noite" do
    tenant = Tenant.create!(name: "Tenant midnight #{SecureRandom.hex(3)}", slug: "tenant-midnight-#{SecureRandom.hex(3)}")
    Setting.set("field_checkin_enabled", "true", tenant: tenant)
    user = create(:admin_user, :field_agent, tenant: tenant)
    store = create(:store, tenant: tenant, auto_checkout_after_minutes: 60, timezone: "America/Sao_Paulo")
    shift = create(:store_shift, tenant: tenant, store: store, admin_user: user,
                   day_of_week: 5, start_time: "18:00", end_time: "23:30")

    # Check-in de ontem às 18:00 (fuso da loja); esqueceu o check-out. O turno
    # terminou 23:30 e a grace de 60min projeta o fechamento para 00:30 de HOJE.
    checked_in = Time.use_zone(store.timezone) { Time.zone.local(2026, 7, 3, 18, 0, 0) }
    check_in = create(:check_in, tenant: tenant, admin_user: user, store: store,
                      store_shift: shift, status: :active, checked_in_at: checked_in)

    # "Agora" = 00:45 do dia seguinte, já passou de 23:30 + 60min = 00:30.
    now = Time.use_zone(store.timezone) { Time.zone.local(2026, 7, 4, 0, 45, 0) }
    travel_to(now) do
      described_class.new.perform(tenant_id: tenant.id)
    end

    expect(check_in.reload.closed_auto_shift_end?).to be true
  end

  it "NÃO fecha antes de shift_end + grace mesmo com relógio virando o dia" do
    tenant = Tenant.create!(name: "Tenant early #{SecureRandom.hex(3)}", slug: "tenant-early-#{SecureRandom.hex(3)}")
    Setting.set("field_checkin_enabled", "true", tenant: tenant)
    user = create(:admin_user, :field_agent, tenant: tenant)
    store = create(:store, tenant: tenant, auto_checkout_after_minutes: 60, timezone: "America/Sao_Paulo")
    shift = create(:store_shift, tenant: tenant, store: store, admin_user: user,
                   day_of_week: 5, start_time: "18:00", end_time: "23:30")

    checked_in = Time.use_zone(store.timezone) { Time.zone.local(2026, 7, 3, 18, 0, 0) }
    check_in = create(:check_in, tenant: tenant, admin_user: user, store: store,
                      store_shift: shift, status: :active, checked_in_at: checked_in)

    # 00:10 — ainda antes de 00:30 (23:30 + 60min): NÃO deve fechar.
    now = Time.use_zone(store.timezone) { Time.zone.local(2026, 7, 4, 0, 10, 0) }
    travel_to(now) do
      described_class.new.perform(tenant_id: tenant.id)
    end

    expect(check_in.reload.active?).to be true
  end
end
