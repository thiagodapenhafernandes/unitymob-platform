require "rails_helper"

RSpec.describe AiPropertySearchHistoryCleanupJob, type: :job do
  it "aplica a retenção configurada somente ao tenant informado" do
    tenant = Tenant.create!(name: "Retenção IA A", slug: "retencao-ia-a", active: true)
    other_tenant = Tenant.create!(name: "Retenção IA B", slug: "retencao-ia-b", active: true)
    PropertySetting.instance(tenant: tenant).update!(ai_property_search_history_retention_days: 10)
    collection = tenant.ai_property_share_collections.create!(admin_user: create(:admin_user, tenant: tenant))
    old_event = collection.audit_events.create!(tenant: tenant, event_type: "collection_created", created_at: 11.days.ago)
    recent_event = collection.audit_events.create!(tenant: tenant, event_type: "interest_created", created_at: 9.days.ago)
    other_collection = other_tenant.ai_property_share_collections.create!(admin_user: create(:admin_user, tenant: other_tenant))
    other_event = other_collection.audit_events.create!(tenant: other_tenant, event_type: "collection_created", created_at: 30.days.ago)

    described_class.perform_now(tenant.id)

    expect(AiPropertyShareAuditEvent.exists?(old_event.id)).to be(false)
    expect(AiPropertyShareAuditEvent.exists?(recent_event.id)).to be(true)
    expect(AiPropertyShareAuditEvent.exists?(other_event.id)).to be(true)
  end
end
