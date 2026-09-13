require "rails_helper"

RSpec.describe Leads::PoolTimeline do
  let(:start) { Time.zone.local(2026, 9, 13, 11, 0, 0) }

  def activity(kind, seconds = 0, **metadata)
    LeadActivity.new(id: seconds + 1, kind: kind, created_at: start + seconds, metadata: metadata)
  end

  it "separa canais, renotificações e ciclos sem confundir envio com entrega ou aceite" do
    events = [
      activity("shark_tank_ready"),
      activity("notification_sent", 1, channel: "whatsapp", notification_context: "shark_tank", admin_user_id: 7, admin_user_name: "Ana",
        whatsapp_delivered_at: (start + 3).iso8601, whatsapp_read_at: (start + 20).iso8601),
      activity("notification_sent", 2, channel: "push", notification_context: "shark_tank", admin_user_id: 7, admin_user_name: "Ana"),
      activity("notification_sent", 5, channel: "whatsapp", notification_context: "pool_renotify", admin_user_id: 7, admin_user_name: "Ana"),
      activity("notification_failed", 6, channel: "whatsapp", notification_context: "pool", admin_user_id: 8, admin_user_name: "Bia"),
      activity("accepted", 30, by: "Ana", shark_tank: true),
      activity("pocket_pool_ready", 120),
      activity("notification_sent", 121, channel: "email", notification_context: "pocket_pool", admin_user_id: 8, admin_user_name: "Bia")
    ]
    pushes = [PushDeliveryEvent.new(admin_user_id: 7, event_type: "device_received", created_at: start + 4)]
    latest, first = described_class.new(events, pushes).cycles
    expect(first.values_at(:notified, :delivered, :read, :accepted, :response_seconds)).to eq([1, 1, 1, 1, 30])
    expect(first[:rows].size).to eq(2)
    expect(first[:rows].first[:points].map { |p| [p[:channel], p[:state]] }).to contain_exactly(
      ["whatsapp", "Enviado"], ["whatsapp", "Recebeu"], ["whatsapp", "Leu"], ["push", "Enviado"], ["push", "Recebeu"], ["attendance", "Atendeu"]
    )
    expect(latest.values_at(:notified, :delivered, :read, :accepted)).to eq([1, 0, 0, 0])
  end

  it "não atribui recebimentos de outra distribuição nem aceita pelo nome quando há homônimos" do
    events = [activity("shark_tank_ready")]
    [7, 8].each do |id|
      events << activity("notification_sent", 1, channel: "push", notification_context: "pool", admin_user_id: id, admin_user_name: "Ana")
    end
    events << activity("accepted", 3, by: "Ana", shark_tank: true)
    events << activity("distributed", 5)
    pushes = [PushDeliveryEvent.new(admin_user_id: 7, event_type: "device_received", created_at: start + 6)]
    cycle = described_class.new(events, pushes).cycles.first
    expect(cycle[:delivered]).to eq(0)
    expect(cycle[:rows].last[:id]).to be_nil
    expect(cycle[:rows].last[:points].first[:state]).to eq("Atendeu")
  end

  it "restringe consulta ao administrador da mesma conta" do
    lead = create(:lead)
    owner = create(:admin_user, :admin, tenant: lead.tenant)
    agent = create(:admin_user, tenant: lead.tenant)
    other_owner = create(:admin_user, :admin, tenant: Tenant.create!(name: "Outra conta", slug: "outra-conta-pool"))
    lead.activities.create!(kind: "shark_tank_ready")
    expect(described_class.for(lead, viewer: owner).size).to eq(1)
    [agent, other_owner, nil].each do |viewer|
      expect(described_class.for(lead, viewer: viewer)).to eq([])
    end
  end

  it "não exibe leads que só passaram pelo rodízio" do
    lead = create(:lead)
    owner = create(:admin_user, :admin, tenant: lead.tenant)
    lead.activities.create!(kind: "notification_sent", metadata: { notification_context: "distribution" })
    expect(described_class.for(lead, viewer: owner)).to eq([])
  end
  it "inclui todos os integrantes sem fabricar entrega e preserva o snapshot após mudar a equipe" do
    rule = create(:distribution_rule, distribution_mode: :shark_tank)
    agents = Array.new(8) { create(:admin_user, :field_agent, tenant: rule.tenant) }
    agents.each { |agent| create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent) }
    lead = create(:lead, tenant: rule.tenant, distribution_rule: rule)
    owner = create(:admin_user, :admin, tenant: rule.tenant)
    snapshot = rule.pool_timeline_participants
    event = lead.activities.create!(kind: "shark_tank_ready", metadata: { rule_id: rule.id, participants: snapshot })
    rule.distribution_rule_agents.delete_all
    cycle = described_class.for(lead.reload, viewer: owner).first
    expect(cycle[:rows].map { |row| row[:id] }).to match_array(agents.map(&:id))
    expect(cycle[:rows].flat_map { |row| row[:points] }).to be_empty
    expect(cycle.values_at(:notified, :delivered, :read, :accepted)).to eq([0, 0, 0, 0])
    event.update!(metadata: { rule_id: rule.id })
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agents.first)
    expect(described_class.for(lead, viewer: owner).first[:rows].map { |row| row[:id] }).to eq([agents.first.id])
  end

end
