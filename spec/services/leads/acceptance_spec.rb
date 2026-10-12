require "rails_helper"

RSpec.describe Leads::Acceptance do
  it "reivindica uma vez, preserva o vencedor e registra uma única atividade" do
    actor = create(:admin_user)
    other = create(:admin_user, tenant: actor.tenant)
    lead = create(:lead, tenant: actor.tenant, admin_user: nil, status: :waiting_acceptance)
    arguments = { tenant: actor.tenant, lead: lead, metadata: { via: "system" }, claim_statuses: [Lead.status_value(:waiting_acceptance)] }
    expect(described_class.call(**arguments, actor: actor)).to eq(:accepted)
    expect(described_class.call(**arguments, actor: actor)).to eq(:already_accepted)
    expect(described_class.call(**arguments, actor: other)).to eq(:taken)
    expect(lead.reload.admin_user_id).to eq(actor.id)
    expect(lead.activities.where(kind: "accepted").count).to eq(1)
  end

  it "reverte a reivindicação se a atividade não puder ser registrada" do
    actor = create(:admin_user)
    lead = create(:lead, tenant: actor.tenant, admin_user: nil, status: :waiting_acceptance)
    allow_any_instance_of(LeadActivity).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    expect {
      described_class.call(tenant: actor.tenant, lead: lead, actor: actor, metadata: {}, claim_statuses: [Lead.status_value(:waiting_acceptance)])
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.status).to eq(Lead.status_value(:waiting_acceptance))
  end

  it "recusa ator de outra conta sem alterar o contexto" do
    actor = create(:admin_user)
    tenant = Tenant.create!(name: "Outra", slug: "acceptance-#{SecureRandom.hex(4)}")
    lead = create(:lead, tenant: tenant, admin_user: nil)
    previous = Current.tenant
    expect(described_class.call(tenant: tenant, lead: lead, actor: actor, metadata: {})).to eq(:ineligible)
    expect(Current.tenant).to eq(previous)
    expect(lead.reload.admin_user_id).to be_nil
  end
end
