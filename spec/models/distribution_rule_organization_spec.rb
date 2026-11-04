require "rails_helper"

RSpec.describe DistributionRule do
  let(:tenant) { Tenant.default }

  it "move só a ordem visual das regras atuais da mesma conta" do
    first = create(:distribution_rule, tenant: tenant, display_position: 0)
    second = create(:distribution_rule, tenant: tenant, display_position: 1)
    archived = create(:distribution_rule, tenant: tenant, active: false, archived_at: Time.current)
    foreign = create(:distribution_rule, tenant: Tenant.create!(name: "Outra conta", slug: "outra-#{SecureRandom.hex(4)}"), display_position: 0)
    second.move_in_display_order!("up")
    expect(tenant.distribution_rules.unarchived.display_order.pluck(:id)).to eq([second.id, first.id])
    expect(archived.reload.display_position).to eq(0)
    expect(foreign.reload.display_position).to eq(0)
    expect(second.reload.active).to be(true)
  end

  it "não permite ativar regra arquivada" do
    rule = create(:distribution_rule, tenant: tenant, active: false, archived_at: Time.current)
    expect(rule.update(active: true)).to be(false)
    expect(tenant.distribution_rules.active).not_to include(rule)
  end

  it "preserva o horário legado e distingue dia fechado de dia sem restrição" do
    rule = build(:distribution_rule, tenant: tenant, represamento_active: true, represamento_schedule: {
      "mon" => { "active" => "false", "start" => "09:00", "end" => "18:00" },
      "tue" => { "mode" => "closed" },
      "wed" => { "mode" => "hours", "start" => "09:00", "end" => "12:00" }
    })
    expect(rule.outside_represamento_hours?(Time.zone.local(2026, 11, 2, 7))).to be(false)
    expect(rule.outside_represamento_hours?(Time.zone.local(2026, 11, 3, 10))).to be(true)
    expect(rule.outside_represamento_hours?(Time.zone.local(2026, 11, 4, 10))).to be(false)
    expect(rule.outside_represamento_hours?(Time.zone.local(2026, 11, 4, 13))).to be(true)
    rule.represamento_schedule["wed"]["start"] = "bad"
    expect(rule).not_to be_valid
  end
end
