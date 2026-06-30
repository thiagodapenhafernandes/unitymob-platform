require "rails_helper"

RSpec.describe CheckIns::AutoCheckoutShiftEndJob do
  include ActiveSupport::Testing::TimeHelpers

  before { Setting.set("field_checkin_enabled", "true") }

  it "quando recebe tenant_id fecha apenas check-ins daquele tenant" do
    travel_to Time.zone.local(2026, 6, 29, 12, 0, 0) do
      current_tenant = Tenant.create!(name: "Tenant auto checkout #{SecureRandom.hex(3)}", slug: "tenant-auto-checkout-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro auto checkout #{SecureRandom.hex(3)}", slug: "outro-auto-checkout-#{SecureRandom.hex(3)}")
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
end
