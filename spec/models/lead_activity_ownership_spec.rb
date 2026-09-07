require "rails_helper"

RSpec.describe "Atividades pertencem ao lead" do
  let(:tenant) { Tenant.default }
  let(:old_owner) { create(:admin_user, tenant: tenant) }
  let(:new_owner) { create(:admin_user, tenant: tenant) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: old_owner, skip_automatic_routing: true) }
  before { Current.tenant = tenant }

  it "transfere todas as pendências, inclusive atrasadas, e preserva autoria e histórico" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: old_owner, created_by: old_owner, due_at: 1.day.ago)
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: old_owner, starts_at: 1.day.ago)
    done = create(:task, tenant: tenant, lead: lead, admin_user: old_owner, status: "concluida")
    cancelled = create(:appointment, tenant: tenant, lead: lead, admin_user: old_owner, status: "cancelado")
    personal = create(:task, tenant: tenant, admin_user: old_owner, lead: nil)
    lead.update!(admin_user: new_owner)
    expect(task.reload.admin_user).to eq(new_owner)
    expect(task.created_by).to eq(old_owner)
    expect(appointment.reload.admin_user).to eq(new_owner)
    expect(done.reload.admin_user).to eq(old_owner)
    expect(cancelled.reload.admin_user).to eq(old_owner)
    expect(personal.reload.admin_user).to eq(old_owner)
    audit = lead.activities.find_by!(kind: "activity_ownership_transferred")
    expect(audit.metadata.dig("changes", "tasks").first).to include("id" => task.id, "from" => old_owner.id, "to" => new_owner.id)
    expect { lead.update!(name: "Outro nome") }.not_to change { lead.activities.where(kind: "activity_ownership_transferred").count }
  end

  it "usa o responsável do lead na criação, edição, revínculo e reabertura" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: new_owner)
    expect(task.admin_user).to eq(old_owner)
    task.update!(admin_user: new_owner)
    expect(task.reload.admin_user).to eq(old_owner)
    task.update!(status: "concluida")
    lead.update!(admin_user: new_owner)
    task.update!(title: "Histórico")
    expect(task.reload.admin_user).to eq(old_owner)
    task.update!(status: "pendente")
    expect(task.reload.admin_user).to eq(new_owner)
    another = create(:lead, tenant: tenant, admin_user: old_owner, skip_automatic_routing: true)
    task.update!(lead: another)
    expect(task.reload.admin_user).to eq(old_owner)
  end

  it "preserva o responsável histórico ao importar atividades já encerradas" do
    lead.update!(admin_user: new_owner)
    task = create(:task, tenant: tenant, lead: lead, admin_user: old_owner, status: "concluida")
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: old_owner, status: "realizado")
    expect(task.reload.admin_user).to eq(old_owner)
    expect(appointment.reload.admin_user).to eq(old_owner)
  end

  it "inclui pendências no aceite atômico e não transfere na corrida perdida" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: old_owner)
    lead.update!(admin_user: nil, status: Lead.status_value(:waiting_acceptance))
    expect(Lead.claim!(lead.id, new_owner.id)).to be(true)
    expect(task.reload.admin_user).to eq(new_owner)
    expect(Lead.claim!(lead.id, old_owner.id)).to be(false)
    expect(task.reload.admin_user).to eq(new_owner)
  end

  it "mantém o escopo da regra no aceite e transfere agenda quando autorizado" do
    rule = create(:distribution_rule, tenant: tenant)
    lead.update!(distribution_rule: rule)
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: old_owner)
    lead.update!(admin_user: nil, status: Lead.status_value(:waiting_acceptance))
    expect(Lead.claim_for_rules!(lead.id, new_owner.id, [rule.id + 1000])).to be(false)
    expect(appointment.reload.admin_user).to eq(old_owner)
    expect(Lead.claim_for_rules!(lead.id, new_owner.id, [rule.id])).to be(true)
    expect(appointment.reload.admin_user).to eq(new_owner)
  end

  it "recusa aceite de outra conta sem alterar suas pendências" do
    other_tenant = Tenant.create!(name: "Outra", slug: "outra-#{SecureRandom.hex(4)}")
    other_owner = create(:admin_user, tenant: other_tenant)
    other_lead = create(:lead, tenant: other_tenant, admin_user: nil, status: :waiting_acceptance, skip_automatic_routing: true)
    Current.tenant = tenant
    expect(Lead.claim!(other_lead.id, other_owner.id)).to be(false)
    expect(other_lead.reload.admin_user_id).to be_nil
  end

  it "reverte também as pendências se a transferência falhar" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: old_owner)
    Lead.transaction do
      lead.update!(admin_user: new_owner)
      raise ActiveRecord::Rollback
    end
    expect(task.reload.admin_user).to eq(old_owner)
    expect(lead.reload.admin_user).to eq(old_owner)
  end

  it "reconcilia o legado de forma idempotente e não altera outra conta" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: old_owner)
    task.update_columns(admin_user_id: new_owner.id)
    other_tenant = Tenant.create!(name: "Outra", slug: "outra-#{SecureRandom.hex(4)}")
    other_user = create(:admin_user, tenant: other_tenant)
    other_task = create(:task, tenant: other_tenant, admin_user: other_user, lead: nil)
    other_task.update_columns(lead_id: lead.id)
    lead.with_lock { lead.sync_open_activity_owners! }
    expect(task.reload.admin_user).to eq(old_owner)
    expect(other_task.reload.admin_user).to eq(other_user)
    expect { lead.with_lock { lead.sync_open_activity_owners! } }.not_to change { lead.activities.count }
  end

  it "transfere as pendências na inativação de usuário" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: old_owner)
    result = AdminUsers::InactivationTransfer.call(user: old_owner, target: new_owner)
    expect(result.leads_count).to eq(1)
    expect(task.reload.admin_user).to eq(new_owner)
    expect(lead.reload.admin_user).to eq(new_owner)
  end
end
