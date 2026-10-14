require "rails_helper"

RSpec.describe Leads::Journey do
  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  def milestone(key)
    described_class.new(lead).milestones.find { |row| row[:key] == key }
  end

  it "não confunde etapa, mensagem automática, visita agendada e proposta aceita com marcos confirmados" do
    lead.update!(status: "Concluido")
    lead.activities.create!(kind: "whatsapp_out", source_category: "automation")
    lead.activities.create!(kind: "note", metadata: { contact_kind: "ligacao", contact_result: "nao_respondeu" })
    create(:appointment, lead: lead, admin_user: admin, status: "agendado")
    Proposal.create!(lead: lead, admin_user: admin, status: "aceita")
    expect(milestone(:contact)[:state]).to include("contato não confirmado")
    expect(milestone(:visit)[:state]).to include("realização pendente")
    expect(milestone(:proposal)[:state]).to include("envio sem evidência")
    expect(milestone(:closing)[:evidence]).to be_empty
  end

  it "reaproveita evidências explícitas sem escrever registros" do
    %w[distributed accepted deal_closed].each { |kind| lead.activities.create!(kind: kind, metadata: { by: admin.name }) }
    lead.activities.create!(kind: "note", metadata: { contact_kind: "ligacao", contact_result: "falou_com_cliente", body: "Cliente respondeu" })
    create(:appointment, lead: lead, admin_user: admin, status: "realizado")
    Proposal.create!(lead: lead, admin_user: admin, status: "enviada", sent_at: Time.current)
    expect { described_class.new(lead).milestones }.not_to change(LeadActivity, :count)
    expect(milestone(:contact)[:state]).to eq("Contato confirmado")
    expect(milestone(:visit)[:state]).to include("realizada")
    expect(milestone(:proposal)[:state]).to eq("Envio registrado")
    expect(milestone(:closing)[:state]).to eq("Declarado no CRM")
  end

  it "não perde a confirmação de contato quando há muitas tentativas mais novas" do
    lead.activities.create!(kind: "note", metadata: { contact_kind: "ligacao", contact_result: "falou_com_cliente" }, created_at: 1.day.ago)
    12.times { lead.activities.create!(kind: "note", metadata: { contact_kind: "ligacao", contact_result: "nao_respondeu" }) }
    expect(milestone(:contact)[:state]).to eq("Contato confirmado")
    expect(milestone(:contact)[:evidence].map { |e| e[:detail] }.join).to include("Falou com cliente")
  end

  it "exclui atividades inconsistentes de outra conta" do
    activity = lead.activities.create!(kind: "deal_closed", metadata: { body: "Não pode aparecer" })
    other = Tenant.create!(name: "Jornada externa", slug: "journey-external-#{SecureRandom.hex(4)}")
    activity.update_column(:tenant_id, other.id)
    expect(milestone(:closing)[:evidence]).to be_empty
  end
end
