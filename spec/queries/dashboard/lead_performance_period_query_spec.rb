require "rails_helper"

RSpec.describe Dashboard::LeadPerformancePeriodQuery do
  let(:admin) { create(:admin_user, :admin) }
  let(:window) { Time.zone.parse("2026-10-01")..Time.zone.parse("2026-10-14").end_of_day }

  def lead_at(date)
    create(:lead, tenant: admin.tenant, admin_user: admin, created_at: Time.zone.parse(date))
  end

  def accepted(lead, at:, pool: false)
    lead.activities.create!(kind: "accepted", created_at: Time.zone.parse(at), metadata: { shark_tank: pool })
  end

  def ids(scope = admin.tenant.leads)
    described_class.new(scope: scope, starts_at: window.begin, ends_at: window.end).call.pluck(:id)
  end

  it "inclui cadastros antigos aceitos no bolsão no período sem duplicar" do
    old = lead_at("2025-01-16")
    accepted(old, at: "2026-10-12", pool: true)
    accepted(old, at: "2026-10-13", pool: true)
    recent = lead_at("2026-10-12")
    accepted(recent, at: "2026-10-13", pool: true)
    expect(ids).to contain_exactly(old.id, recent.id)
  end

  it "reconhece aceite após entrada no pocket e exclui aceite fora do período" do
    old = lead_at("2025-01-16")
    old.activities.create!(kind: "pocket_pool_ready", created_at: Time.zone.parse("2026-09-30"))
    accepted(old, at: "2026-10-12")
    outside = lead_at("2025-01-17")
    accepted(outside, at: "2026-09-30", pool: true)
    expect(ids).to contain_exactly(old.id)
  end

  it "não inclui aceite comum nem entrada posterior ao aceite" do
    regular = lead_at("2025-01-16")
    accepted(regular, at: "2026-10-12")
    regular.activities.create!(kind: "pocket_pool_ready", created_at: Time.zone.parse("2026-10-13"))
    expect(ids).to be_empty
  end

  it "preserva o escopo autorizado recebido" do
    lead = lead_at("2025-01-16")
    accepted(lead, at: "2026-10-12", pool: true)
    expect(ids(admin.tenant.leads.where(admin_user_id: nil))).to be_empty
  end
end
