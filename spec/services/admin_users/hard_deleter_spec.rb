require "rails_helper"

RSpec.describe AdminUsers::HardDeleter do
  let(:tenant) { Tenant.create!(name: "Tenant deleter #{SecureRandom.hex(3)}", slug: "tenant-deleter-#{SecureRandom.hex(3)}") }
  let(:user) { create(:admin_user, tenant: tenant) }
  let(:target) { create(:admin_user, tenant: tenant) }

  around do |example|
    previous = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous
  end

  it "cobre todas as FKs reais para admin_users" do
    expect { described_class.new(user, target).send(:verify_coverage!) }.not_to raise_error
  end

  it "usa apenas tabelas e colunas existentes nos mapas" do
    conn = ActiveRecord::Base.connection
    maps = [
      described_class::DROPPED_FK,
      described_class::MODEL_HANDLED,
      described_class::REASSIGN,
      described_class::DESTROY,
      described_class::NULLIFY
    ]
    maps.each do |map|
      map.each do |table, cols|
        expect(conn.tables).to include(table)
        cols.each { |col| expect(conn.columns(table).map(&:name)).to include(col), "#{table}.#{col}" }
      end
    end
  end

  it "reatribui, nulifica e apaga as referências e retorna as contagens" do
    lead_a = create(:lead, tenant: tenant, admin_user: user)
    lead_b = create(:lead, tenant: tenant, admin_user: user)
    habitation = create(:habitation, tenant: tenant, admin_user: user)
    terms = CommercialContractTermsVersion.create!(tenant: tenant, version: "v1", title: "Termos", body: "corpo")
    proposal = CommercialContractProposal.new(
      tenant: tenant, admin_user: user, terms_version: terms, public_token: SecureRandom.hex(16),
      title: "Proposta", legal_business_name: "Empresa", cnpj: "00.000.000/0001-00", plan_name: "Plano"
    )
    proposal.save!(validate: false)
    collection = AiPropertyShareCollection.create!(
      tenant: tenant, admin_user: user, token: SecureRandom.hex(16), expires_at: 1.day.from_now
    )
    favorite = create(:lead_favorite, tenant: tenant, admin_user: user, lead: create(:lead, tenant: tenant))
    notification = InAppNotification.create!(tenant_id: tenant.id, admin_user: user, kind: "geral", title: "Oi")
    archived = create(:lead, tenant: tenant, archived_by_admin_user: user)
    history = AiPropertySearchHistory.create!(tenant: tenant, admin_user: user, status: "completed")
    photo_share = HabitationPhotoShare.create!(
      habitation: habitation, token: SecureRandom.hex(16), admin_user: user, photo_ids: [1]
    )
    usage = OpenAiUsageEvent.create!(tenant: tenant, feature: "busca", admin_user: user)
    contract_event = CommercialContractEvent.create!(tenant: tenant, proposal: proposal, event_type: "created", admin_user: user)
    audit_event = AiPropertyShareAuditEvent.create!(
      tenant: tenant, ai_property_share_collection: collection, event_type: "viewed", admin_user: user
    )
    integration = create(:external_lead_integration, connected_by_admin_user: user)
    session = OperationalUserSession.create!(
      admin_user: user, token: SecureRandom.hex(16), started_at: 1.hour.ago, last_seen_at: Time.current,
      duration_seconds: 0, events_count: 0
    )
    op_event = OperationalUserEvent.create!(
      admin_user: user, operational_user_session: session, name: "catalog_search", occurred_at: Time.current
    )

    result = described_class.call(user: user, target: target)

    expect(AdminUser.exists?(user.id)).to be(false)
    expect(lead_a.reload.admin_user_id).to eq(target.id)
    expect(lead_b.reload.admin_user_id).to eq(target.id)
    expect(habitation.reload.admin_user_id).to eq(target.id)
    expect(proposal.reload.admin_user_id).to eq(target.id)
    expect(collection.reload.admin_user_id).to eq(target.id)
    expect(LeadFavorite.exists?(favorite.id)).to be(false)
    expect(InAppNotification.exists?(notification.id)).to be(false)
    expect(OperationalUserEvent.exists?(op_event.id)).to be(false)
    expect(OperationalUserSession.exists?(session.id)).to be(false)
    expect(archived.reload.archived_by_admin_user_id).to be_nil
    expect(AiPropertySearchHistory.exists?(history.id)).to be(false)
    expect(HabitationPhotoShare.exists?(photo_share.id)).to be(false)
    expect(usage.reload.admin_user_id).to be_nil
    expect(contract_event.reload.admin_user_id).to be_nil
    expect(audit_event.reload.admin_user_id).to be_nil
    expect(integration.reload.connected_by_admin_user_id).to be_nil
    expect(result.leads_count).to eq(2)
    expect(result.habitations_count).to eq(1)
  end
end
