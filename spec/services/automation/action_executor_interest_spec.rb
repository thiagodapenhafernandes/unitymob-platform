require "rails_helper"

RSpec.describe Automation::ActionExecutor do
  let(:admin) { create(:admin_user, :admin, email: "interest-action-#{SecureRandom.hex(6)}@salute.test") }
  let(:lead) { create(:lead, admin_user: admin, name: "Maria") }

  before do
    LayoutSetting.instance.update!(
      interest_intelligence_enabled: true,
      interest_intelligence_settings: InterestIntelligence::Settings::DEFAULTS.merge(
        "minimum_match_score" => 50,
        "broker_review_required" => true,
        "allow_direct_lead_message" => false
      )
    )

    viewed = create(
      :habitation,
      titulo_anuncio: "Apartamento visto",
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 1_000_000_00
    )
    create(
      :habitation,
      titulo_anuncio: "Apartamento compatível",
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 1_020_000_00
    )
    session = PublicNavigationSession.create!(lead: lead, token: SecureRandom.uuid)
    session.events.create!(
      lead: lead,
      habitation: viewed,
      name: "property_view",
      property_snapshot: {
        city: "Balneário Camboriú",
        neighborhood: "Centro",
        category: "Apartamento",
        bedrooms: 3,
        price_cents: 1_000_000_00
      }
    )

    allow(InterestIntelligence::AiSummary).to receive(:call).and_return(
      {
        "classification" => "quente",
        "summary" => "Lead com interesse claro em apartamento no Centro.",
        "broker_message" => "Priorize contato com curadoria.",
        "lead_message" => "Separei algumas opções compatíveis para você.",
        "rationale" => ["visitou imóvel compatível"]
      }
    )
  end

  it "creates a broker task for an interest opportunity" do
    expect do
      described_class.execute(
        {
          type: "notify_broker_interest_opportunity",
          title: "Revisar oportunidade",
          due_in_hours: 1
        },
        lead
      )
    end.to change(Task, :count).by(1)
      .and change(LeadActivity.where(kind: "task_created"), :count).by(1)

    task = Task.last
    expect(task.title).to eq("Revisar oportunidade")
    expect(task.tenant).to eq(lead.tenant)
    expect(task.description).to include("Lead com interesse claro")
    expect(task.description).to include("Apartamento compatível")
  end

  it "uses the configured fallback user when the lead has no responsible user" do
    fallback = create(:admin_user, :admin, email: "fallback-interest-#{SecureRandom.hex(6)}@salute.test")
    lead.update!(admin_user: nil)

    described_class.execute(
      {
        type: "notify_broker_interest_opportunity",
        title: "Revisar oportunidade",
        fallback_admin_user_id: fallback.id
      },
      lead
    )

    expect(Task.last.admin_user).to eq(fallback)
  end

  it "ignores configured fallback users from another Tenant" do
    lead_tenant = Tenant.create!(name: "Lead tenant #{SecureRandom.hex(3)}", slug: "lead-tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Other tenant #{SecureRandom.hex(3)}", slug: "other-tenant-#{SecureRandom.hex(3)}")
    lead_profile = lead_tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    tenant_fallback = create(:admin_user, tenant: lead_tenant, profile: lead_profile, email: "tenant-fallback-#{SecureRandom.hex(6)}@salute.test")
    other_fallback = create(:admin_user, tenant: other_tenant, profile: other_profile, email: "other-fallback-#{SecureRandom.hex(6)}@salute.test")
    lead.update!(tenant: lead_tenant, admin_user: nil)

    described_class.execute(
      {
        type: "notify_broker_interest_opportunity",
        title: "Revisar oportunidade",
        fallback_admin_user_id: other_fallback.id
      },
      lead
    )

    expect(Task.last.admin_user).to eq(tenant_fallback)
  end

  it "keeps the current lead responsible before using the configured fallback" do
    fallback = create(:admin_user, :admin, email: "fallback-unused-#{SecureRandom.hex(6)}@salute.test")

    described_class.execute(
      {
        type: "notify_broker_interest_opportunity",
        title: "Revisar oportunidade",
        fallback_admin_user_id: fallback.id
      },
      lead
    )

    expect(Task.last.admin_user).to eq(admin)
  end

  it "stores a WhatsApp draft instead of sending directly when review is required" do
    expect do
      described_class.execute(
        {
          type: "prepare_matching_properties_whatsapp",
          message_prefix: "Olá, {{nome}}.",
          limit: 2
        },
        lead
      )
    end.to change(LeadActivity.where(kind: "note"), :count).by(1)
      .and change(Task, :count).by(1)

    note = LeadActivity.where(kind: "note").last
    expect(note.metadata["contact_kind"]).to eq("rascunho WhatsApp")
    expect(note.metadata["body"]).to include("Olá, Maria.")
    expect(note.metadata["body"]).to include("Separei algumas opções")
  end
end
