require "rails_helper"

RSpec.describe InterestIntelligence::Journey do
  let(:lead) { create(:lead, admin_user: create(:admin_user)) }
  let(:session) { PublicNavigationSession.create!(lead: lead, tenant: lead.tenant) }

  def contact(result, at: Time.current)
    lead.activities.create!(kind: "note", metadata: { contact_kind: "whatsapp", contact_result: result }, created_at: at)
  end

  it "separa ausência de sinais, pesquisa e tentativas sem resposta" do
    expect(described_class.call(lead)[:classification]).to eq("sem_sinais")
    contact("nao_respondeu")
    expect(described_class.call(lead)[:classification]).to eq("frio")
    session.events.create!(lead: lead, name: "property_view")
    expect(described_class.call(lead)[:classification]).to eq("morno")
    contact("sem_interesse", at: 1.second.from_now)
    expect(described_class.call(lead)[:label]).to eq("Revisar interesse")
  end

  it "não aquece por visitas antigas ou conversas antigas" do
    contact("falou_com_cliente", at: 30.days.ago)
    create(:appointment, lead: lead, admin_user: lead.admin_user, status: "realizado", starts_at: 30.days.ago)
    expect(described_class.call(lead)[:classification]).to eq("frio")
  end

  it "considera o compromisso de visita e depois o encerramento sem reabrir" do
    create(:appointment, lead: lead, admin_user: lead.admin_user)
    expect(described_class.call(lead)[:label]).to eq("Visita agendada")
    lead.update_columns(closed_at: 1.day.ago)
    session.events.create!(lead: lead, name: "property_view")
    reading = described_class.call(lead.reload)
    expect(reading).to include(classification: "encerrado", label: "Avaliar retomada", next_activity: nil)
    expect(lead.reload.closed_at).to be_present
  end

  it "respeita retorno combinado e proposta válida sem depender de cliques" do
    contact("retornar_depois")
    create(:appointment, lead: lead, admin_user: lead.admin_user, kind: "ligacao")
    expect(described_class.call(lead)[:classification]).to eq("retorno_combinado")
    contact("falou_com_cliente", at: 1.second.from_now)
    lead.proposals.create!(admin_user: lead.admin_user, status: "enviada", valor_cents: 0, entrada_cents: 0)
    expect(described_class.call(lead)[:label]).to eq("Em negociação")
  end
  it "distingue abrir uma seleção de declarar interesse e conta imóveis sem repetição" do
    property = create(:habitation, tenant: lead.tenant)
    collection = lead.ai_property_share_collections.create!(admin_user: lead.admin_user, tenant: lead.tenant)
    collection.record!("collection_opened", lead: lead)
    expect(described_class.call(lead)).to include(classification: "morno", viewed_count: 0, declared_count: 0)
    2.times { collection.record!("property_opened", lead: lead, habitation: property) }
    session.events.create!(lead: lead, habitation: property, name: "property_view")
    expect(described_class.call(lead)[:viewed_count]).to eq(1)
    collection.record!("interest_created", lead: lead, habitation: property)
    expect(described_class.call(lead)).to include(classification: "quente", declared_count: 1)
    lead.update_columns(archived_at: Time.current)
    expect(described_class.call(lead.reload)).to include(classification: "encerrado", label: "Encerrado sem negócio")
  end

end
