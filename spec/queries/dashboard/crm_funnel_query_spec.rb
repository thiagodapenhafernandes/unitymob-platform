require "rails_helper"

RSpec.describe Dashboard::CrmFunnelQuery do
  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: owner, skip_automatic_routing: true, created_at: 3.days.ago) }
  def result(scope = Lead.all)
    described_class.new(scope: scope, tenant: tenant, starts_at: 30.days.ago, ends_at: Time.current).call
  end

  it "conta leads visitados uma vez e separa agendamentos vencidos" do
    2.times { create(:appointment, tenant: tenant, lead: lead, admin_user: owner, status: "realizado", starts_at: 1.day.ago) }
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, status: "agendado", starts_at: 1.day.ago)
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: "reuniao", status: "realizado")
    data = result
    expect(data[:counts]).to include(leads: 1, qualified: 0, visited: 1, proposed: 0)
    expect(data[:completed_visits]).to eq(2)
    expect(data[:gaps]).to include(unassessed: 1, overdue_visits: 1, visited_without_qualification: 1)
  end

  it "usa qualificação de qualquer papel e respeita período, conta e escopo autorizado" do
    lead.update_columns(manager_qualification_status: "qualified")
    create(:lead, tenant: tenant, admin_user: owner, skip_automatic_routing: true, created_at: 40.days.ago)
    other = Tenant.create!(name: "Outra conta", slug: "funnel-#{SecureRandom.hex(4)}")
    create(:lead, tenant: other, skip_automatic_routing: true)
    data = result(Lead.where(id: lead.id))
    expect(data[:counts]).to include(leads: 1, qualified: 1)
    expect(data[:gaps][:unassessed]).to eq(0)
    expect(result(Lead.none)[:counts].values).to all(eq(0))
  end

  it "não transforma rascunho em proposta enviada nem proposta aceita em venda" do
    Proposal.create!(lead: lead, admin_user: owner, status: "rascunho")
    proposal = Proposal.create!(lead: lead, admin_user: owner, status: "aceita", sent_at: 1.day.ago)
    data = result
    expect(data[:draft_proposals]).to eq(1)
    expect(data[:counts]).to include(proposed: 1, won: 0)
    proposal.update_columns(sent_at: nil)
    expect(result[:counts][:proposed]).to eq(0)
  end

  it "reutiliza o contrato de ganho do CRM sem inferir receita" do
    stage = tenant.lead_pipeline_stages.find_by!(stage_type: "won")
    lead.update_columns(status: stage.name, lead_pipeline_stage_id: stage.id)
    expect(result[:counts][:won]).to eq(1)
    expect(result[:legacy_wins]).to eq(0)
  end
end
