require "rails_helper"

RSpec.describe Leads::OperationalScope do
  let(:tenant) { Tenant.default }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant) }

  it "exclui arquivamento explícito e etapa arquivada, preservando leads e status perdidos" do
    archived = create(:lead_pipeline_stage, lead_pipeline: pipeline, name: "Histórico", stage_type: "archived")
    active = create(:lead, tenant: tenant, lead_pipeline: pipeline)
    stamped = create(:lead, tenant: tenant, lead_pipeline: pipeline)
    stamped.update_columns(archived_at: Time.current)
    staged = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: archived, status: archived.name)
    legacy = create(:lead, tenant: tenant, lead_pipeline: pipeline)
    legacy.update_columns(lead_pipeline_stage_id: nil, status: archived.name)
    lost = create(:lead, tenant: tenant, lead_pipeline: pipeline, status: "Descartado")
    imported = create(:lead, tenant: tenant, lead_pipeline: pipeline, status: "Descartado",
      attribution_data: { "archive_details" => { "archived" => true } })
    ids = described_class.without_archived(tenant.leads, tenant: tenant).pluck(:id)
    expect(ids).to include(active.id, lost.id)
    expect(ids).not_to include(stamped.id, staged.id, legacy.id, imported.id)
    expect(described_class.archived(tenant.leads, tenant: tenant).pluck(:id)).to match_array([stamped.id, staged.id, legacy.id, imported.id])
    expect(tenant.leads.where(id: [stamped.id, staged.id, legacy.id]).count).to eq(3)
  end

  it "não usa o nome de uma etapa arquivada de outra conta ou outro funil" do
    other = Tenant.create!(name: "Outra", slug: "archive-#{SecureRandom.hex(4)}")
    other_pipeline = create(:lead_pipeline, tenant: other)
    create(:lead_pipeline_stage, lead_pipeline: other_pipeline, name: "Reservado", stage_type: "archived")
    own_other_pipeline = create(:lead_pipeline, tenant: tenant)
    create(:lead_pipeline_stage, lead_pipeline: own_other_pipeline, name: "Reservado", stage_type: "archived")
    active = create(:lead, tenant: tenant, lead_pipeline: pipeline)
    active.update_columns(status: "Reservado", lead_pipeline_stage_id: nil)
    expect(described_class.without_archived(tenant.leads, tenant: tenant)).to include(active)
  end
end
