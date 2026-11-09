require "rails_helper"

RSpec.describe "Campanhas permitidas na distribuição" do
  let(:tenant) { Tenant.default }
  let(:rule) { create(:distribution_rule, tenant: tenant) }
  let(:restricted) { create(:admin_user, :field_agent, tenant: tenant) }
  let(:unrestricted) { create(:admin_user, :field_agent, tenant: tenant) }
  let!(:membership) do
    MetaCampaignInsight.create!(tenant: tenant, campaign_id: "12345", campaign_name: "Gralha Azul", date: Date.current)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: restricted, position: 1, allowed_meta_campaign_ids: ["12345"])
  end

  around do |example|
    Current.set(tenant: tenant) { example.run }
  end

  def lead_for(id = nil)
    create(:lead, tenant: tenant, skip_automatic_routing: true, other_information: {"meta_campaign_id" => id})
  end

  it "mantém todas por padrão; filtra por ID exato e recusa campanha ausente" do
    other = create(:distribution_rule_agent, distribution_rule: rule, admin_user: unrestricted, position: 2)
    expect(other.allowed_meta_campaign_ids).to eq([])
    expect(rule.candidates_for(lead_for("12345")).pluck(:admin_user_id)).to contain_exactly(restricted.id, unrestricted.id)
    [nil, "99999", "123456"].each do |id|
      expect(rule.candidates_for(lead_for(id)).pluck(:admin_user_id)).to eq([unrestricted.id])
    end
  end

  it "não entrega para restrito no rotativo ou ponderado e preserva o lead se ninguém atende" do
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: unrestricted, position: 2)
    %i[rotary performance].each do |mode|
      rule.update!(distribution_mode: mode)
      lead = lead_for
      Leads::DistributorService.distribute_to(lead, rule)
      expect(lead.reload.admin_user_id).to eq(unrestricted.id)
    end
    rule.distribution_rule_agents.where(admin_user_id: unrestricted.id).destroy_all
    lead = lead_for
    Leads::DistributorService.distribute_to(lead, rule)
    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.status).to eq(Lead.status_value(:represado))
    expect(lead.activities.where(kind: "distribution_failed").last.metadata["reason"]).to eq("no_eligible_agent_for_campaign")
  end

  it "permite a campanha selecionada e bloqueia o atendimento direto de outra campanha" do
    allowed = lead_for("12345")
    expect(Leads::DistributorService.distribute_to_agent(allowed, rule, restricted)).to eq(rule)
    expect(allowed.reload.admin_user_id).to eq(restricted.id)
    unknown = lead_for
    expect(Leads::DistributorService.distribute_to_agent(unknown, rule, restricted)).to be_nil
    expect(unknown.reload.admin_user_id).to be_nil
  end

  it "bloqueia reivindicação no bolsão, mas permite campanha autorizada" do
    unknown = lead_for
    unknown.update!(distribution_rule: rule, status: :waiting_acceptance)
    expect(Lead.claim_for_rules!(unknown.id, restricted.id, [rule.id])).to be(false)
    unknown.update!(other_information: {"meta_campaign_id" => "12345"})
    expect(Lead.claim_for_rules!(unknown.id, restricted.id, [rule.id])).to be(true)
  end

  it "não reutiliza a campanha antiga após entrada sem campanha identificada" do
    lead = lead_for("12345")
    lead.update!(other_information: {"meta_campaign_id" => "12345", "distribution_entry" => {"meta_campaign_id" => nil}})
    expect(rule.candidates_for(lead)).to be_empty
  end

  it "não usa fidelização fora da regra para contornar a restrição" do
    LeadSetting.instance(tenant: tenant).update!(stickiness_enabled: true,
      stickiness_match: "phone_or_email", stickiness_owner: "attended", stickiness_fallback: "active_any", stickiness_window_days: nil)
    previous = lead_for("12345")
    previous.update!(admin_user: restricted, status: :em_atendimento)
    incoming = lead_for
    incoming.update!(phone: previous.phone, email: previous.email)
    expect(Leads::StickyAssignment.corretor_for(incoming, rule, candidates: rule.candidates_for(incoming))).to be_nil
  end

  it "não notifica corretor restrito no bolsão de campanha desconhecida" do
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: unrestricted)
    LeadSetting.instance(tenant: tenant).update!(notify_on_shark_tank: true)
    dispatcher = instance_double(Leads::NotificationDispatcher)
    allow(Leads::NotificationDispatcher).to receive(:new).and_return(dispatcher)
    expect(dispatcher).to receive(:deliver_to_agent).with(unrestricted, pool: true, notification_context: "pool")
    expect(dispatcher).not_to receive(:deliver_to_agent).with(restricted, anything)
    Leads::NotificationDispatcher.notify_pool(lead_for, rule)
  end

  it "recusa campanhas de outra conta e conserva a restrição salva" do
    other = Tenant.create!(name: "Outra", slug: "campaigns-#{SecureRandom.hex(4)}")
    MetaCampaignInsight.create!(tenant: other, campaign_id: "99999", campaign_name: "Privada", date: Date.current)
    expect(membership.update(allowed_meta_campaign_ids: ["99999"])).to be(false)
    expect(membership.reload.allowed_meta_campaign_ids).to eq(["12345"])
    membership.update!(weight: 3)
    expect(membership.allowed_meta_campaign_ids).to eq(["12345"])
  end
end
