require "rails_helper"

RSpec.describe Task, type: :model do
  def create_tenant_with_profile(name)
    tenant = Tenant.create!(name: name, slug: "#{name.parameterize}-#{SecureRandom.hex(3)}")
    profile = Profile.create!(tenant: tenant, name: "Operacional", axis: "vertical", position: 50)
    [tenant, profile]
  end

  it "rejeita responsável e criador de outra conta" do
    tenant, profile = create_tenant_with_profile("Conta Tarefa A")
    other_tenant, other_profile = create_tenant_with_profile("Conta Tarefa B")
    owner = create(:admin_user, tenant: tenant, profile: profile)
    other_owner = create(:admin_user, tenant: other_tenant, profile: other_profile)

    task = described_class.new(
      tenant: tenant,
      admin_user: other_owner,
      created_by: other_owner,
      title: "Follow-up",
      kind: "follow_up",
      status: "pendente"
    )

    expect(task).not_to be_valid
    expect(task.errors[:admin_user]).to include("deve pertencer à mesma conta da tarefa")
    expect(task.errors[:created_by]).to include("deve pertencer à mesma conta da tarefa")
    expect(owner.tenant_id).to eq(tenant.id)
  end

  it "rejeita lead de outra conta" do
    tenant, profile = create_tenant_with_profile("Conta Tarefa C")
    other_tenant = Tenant.create!(name: "Conta Tarefa D", slug: "conta-tarefa-d-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, tenant: tenant, profile: profile)
    lead = build(:lead, tenant: other_tenant)

    task = described_class.new(
      tenant: tenant,
      admin_user: owner,
      lead: lead,
      title: "Follow-up",
      kind: "follow_up",
      status: "pendente"
    )

    expect(task).not_to be_valid
    expect(task.errors[:lead]).to include("deve pertencer à mesma conta da tarefa")
  end

  describe ".operational_current" do
    it "inclui tarefa C2S pendente quando o lead ainda esta ativo operacionalmente" do
      tenant, profile = create_tenant_with_profile("Conta Tarefa C2S Ativa")
      owner = create(:admin_user, tenant: tenant, profile: profile)
      lead = create(:lead, tenant: tenant, admin_user: owner, status: "Em Atendimento")
      task = create(:task, tenant: tenant, lead: lead, admin_user: owner, source: "external_legacy")

      expect(described_class.operational_current).to include(task)
    end

    it "mantem fora da agenda operacional tarefa C2S de lead nao operacional" do
      tenant, profile = create_tenant_with_profile("Conta Tarefa C2S Fechada")
      owner = create(:admin_user, tenant: tenant, profile: profile)
      pipeline = LeadPipeline.ensure_default!(tenant: tenant)
      closed_stage = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Descartado", stage_type: "lost")
      lead = create(:lead, tenant: tenant, admin_user: owner, lead_pipeline: pipeline, lead_pipeline_stage: closed_stage, status: closed_stage.name)
      task = create(:task, tenant: tenant, lead: lead, admin_user: owner, source: "external_legacy")

      expect(described_class.operational_current).not_to include(task)
      expect(described_class.external_legacy).to include(task)
    end
  end
end
