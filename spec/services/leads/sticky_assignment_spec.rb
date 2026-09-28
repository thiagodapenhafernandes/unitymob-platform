require "rails_helper"

RSpec.describe Leads::StickyAssignment do
  let(:tenant) { Tenant.create!(name: "Tenant sticky #{SecureRandom.hex(3)}", slug: "tenant-sticky-#{SecureRandom.hex(3)}") }
  let(:other_tenant) { Tenant.create!(name: "Outro sticky #{SecureRandom.hex(3)}", slug: "outro-sticky-#{SecureRandom.hex(3)}") }

  it "não reaproveita corretor de lead anterior de outro tenant" do
    setting = LeadSetting.instance(tenant: tenant)
    setting.update!(
      stickiness_enabled: true,
      stickiness_match: "phone",
      stickiness_owner: "any_assignment",
      stickiness_fallback: "active_any",
      stickiness_window_days: 30
    )
    other_agent_profile = other_tenant.profiles.find_by!(key: "agent")
    other_agent = create(:admin_user, tenant: other_tenant, profile: other_agent_profile, active: true)
    current_lead = create(:lead, tenant: tenant, phone: "5547999990000", admin_user: nil)
    create(:lead, tenant: other_tenant, phone: "5547999990000", admin_user: other_agent, updated_at: 1.day.ago)
    rule = create(:distribution_rule, tenant: tenant)

    result = described_class.corretor_for(current_lead, rule, candidates: [])

    expect(result).to be_nil
  end

  it "reaproveita corretor anterior apenas dentro do mesmo tenant" do
    LeadSetting.instance(tenant: tenant).update!(
      stickiness_enabled: true,
      stickiness_match: "phone",
      stickiness_owner: "any_assignment",
      stickiness_fallback: "active_any",
      stickiness_window_days: 30
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    agent = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    current_lead = create(:lead, tenant: tenant, phone: "5547999990000", admin_user: nil)
    create(:lead, tenant: tenant, phone: "5547999990000", admin_user: agent, updated_at: 1.day.ago)
    rule = create(:distribution_rule, tenant: tenant)

    result = described_class.corretor_for(current_lead, rule, candidates: [])

    expect(result).to eq(agent)
  end

  it "mantem o dono do lead anterior criado por ultimo mesmo que outro tenha sido atualizado depois" do
    LeadSetting.instance(tenant: tenant).update!(
      stickiness_enabled: true,
      stickiness_match: "phone_or_email",
      stickiness_owner: "attended",
      stickiness_fallback: "active_in_rule",
      stickiness_window_days: nil
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    augusto = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    lidia = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    phone = "5515997750237"
    # Lead antigo da Lidia tocado por sync externo depois (updated_at maior).
    old_lead = create(:lead, tenant: tenant, phone: phone, admin_user: lidia, status: :em_atendimento)
    old_lead.update_columns(created_at: 30.days.ago, updated_at: 1.hour.ago)
    recent_lead = create(:lead, tenant: tenant, phone: phone, admin_user: augusto, status: :em_atendimento)
    recent_lead.update_columns(created_at: 2.days.ago, updated_at: 2.days.ago)
    current_lead = create(:lead, tenant: tenant, phone: phone, admin_user: nil)
    rule = create(:distribution_rule, tenant: tenant)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: augusto)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: lidia)

    result = described_class.corretor_for(current_lead, rule, candidates: rule.distribution_rule_agents.to_a)

    expect(result).to eq(augusto)
  end

  it "usa o proximo dono mais recente quando o ultimo nao e candidato da regra" do
    LeadSetting.instance(tenant: tenant).update!(
      stickiness_enabled: true,
      stickiness_match: "phone_or_email",
      stickiness_owner: "attended",
      stickiness_fallback: "active_in_rule",
      stickiness_window_days: nil
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    augusto = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    lidia = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    phone = "5515997751111"
    old_lead = create(:lead, tenant: tenant, phone: phone, admin_user: augusto, status: :em_atendimento)
    old_lead.update_columns(created_at: 5.days.ago, updated_at: 5.days.ago)
    recent_lead = create(:lead, tenant: tenant, phone: phone, admin_user: lidia, status: :em_atendimento)
    recent_lead.update_columns(created_at: 1.day.ago, updated_at: 1.day.ago)
    current_lead = create(:lead, tenant: tenant, phone: phone, admin_user: nil)
    rule = create(:distribution_rule, tenant: tenant)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: augusto)

    result = described_class.corretor_for(current_lead, rule, candidates: rule.distribution_rule_agents.to_a)

    expect(result).to eq(augusto)
  end

  it "desiste para o rodizio quando nenhum dono anterior e elegivel" do
    LeadSetting.instance(tenant: tenant).update!(
      stickiness_enabled: true,
      stickiness_match: "phone_or_email",
      stickiness_owner: "attended",
      stickiness_fallback: "active_in_rule",
      stickiness_window_days: nil
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    augusto = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    lidia = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    current_lead = create(:lead, tenant: tenant, phone: "5515997752222", admin_user: nil)
    create(:lead, tenant: tenant, phone: "5515997752222", admin_user: lidia, status: :em_atendimento)
    rule = create(:distribution_rule, tenant: tenant)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: augusto)

    result = described_class.corretor_for(current_lead, rule, candidates: rule.distribution_rule_agents.to_a)

    expect(result).to be_nil
  end

  it "redistribui quando o lead anterior esta em etapa configurada para nao fidelizar" do
    pipeline = LeadPipeline.ensure_default!(tenant: tenant)
    archived_stage = pipeline.stages.find_by!(stage_type: "archived")
    LeadSetting.instance(tenant: tenant).update!(
      stickiness_enabled: true,
      stickiness_match: "phone",
      stickiness_owner: "any_assignment",
      stickiness_fallback: "active_any",
      stickiness_window_days: 30,
      stickiness_non_fidelizing_stage_ids: [archived_stage.id]
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    agent = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    current_lead = create(:lead, tenant: tenant, phone: "5547999990000", admin_user: nil)
    create(
      :lead,
      tenant: tenant,
      phone: "5547999990000",
      admin_user: agent,
      lead_pipeline: pipeline,
      lead_pipeline_stage: archived_stage,
      status: archived_stage.name,
      updated_at: 1.day.ago
    )
    rule = create(:distribution_rule, tenant: tenant)

    result = described_class.corretor_for(current_lead, rule, candidates: [])

    expect(result).to be_nil
  end
end
