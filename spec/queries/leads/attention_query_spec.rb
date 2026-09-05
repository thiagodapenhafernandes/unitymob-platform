require "rails_helper"

RSpec.describe Leads::AttentionQuery do
  include ActiveSupport::Testing::TimeHelpers

  it "preserva relação autorizada, contato registrado e limite do SLA" do
    freeze_time do
      tenant = Tenant.create!(name: "Attention", slug: "attention-#{SecureRandom.hex(4)}")
      other = Tenant.create!(name: "Other attention", slug: "other-attention-#{SecureRandom.hex(4)}")
      user = create(:admin_user, tenant: tenant)
      overdue = create(:lead, tenant: tenant, admin_user: user, created_at: 7.hours.ago)
      contacted = create(:lead, tenant: tenant, admin_user: user, created_at: 7.hours.ago)
      boundary = create(:lead, tenant: tenant, admin_user: user, created_at: 6.hours.ago)
      unassigned = create(:lead, tenant: tenant, admin_user: nil)
      create(:lead, tenant: other, admin_user: nil)
      LeadActivity.create!(lead: contacted, kind: "accepted")
      scope = tenant.leads.where(id: [overdue.id, contacted.id, boundary.id, unassigned.id]).order(:id)
      result = described_class.new(scope: scope, sla_hours: 6, contact_kinds: %w[accepted], now: Time.current).call
      expect(result.pluck(:id)).to eq([overdue.id, unassigned.id].sort)
      narrowed = described_class.new(scope: scope.where(id: overdue.id), sla_hours: 6, contact_kinds: %w[accepted]).call
      expect(narrowed.pluck(:id)).to eq([overdue.id])
    end
  end
end
