require "rails_helper"

RSpec.describe "Admin::LeadStatuses", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "lead-status-admin-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outro status #{SecureRandom.hex(3)}", slug: "outro-status-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista apenas etapas do funil e tenant atual" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    pipeline.stages.create!(tenant: admin.tenant, name: "Em análise")
    other_current_pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Locação")
    create(:lead_pipeline_stage, lead_pipeline: other_current_pipeline, tenant: admin.tenant, name: "Visita locação")
    other_pipeline = LeadPipeline.ensure_default!(tenant: other_tenant)
    other_pipeline.stages.create!(tenant: other_tenant, name: "Status externo")

    get admin_lead_statuses_path(lead_pipeline_id: pipeline.id), headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body).map { |row| row.fetch("name") }
    expect(names).to include("Em análise")
    expect(names).not_to include("Visita locação")
    expect(names).not_to include("Status externo")
  end

  it "ignora update de etapa de outro tenant e cria novas etapas no funil atual" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    external_stage = LeadPipeline.ensure_default!(tenant: other_tenant).stages.create!(tenant: other_tenant, name: "Status externo")

    post bulk_update_admin_lead_statuses_path,
         params: {
           lead_pipeline_id: pipeline.id,
           statuses: [
             { id: external_stage.id, name: "Invadido", description: "Nao deve mudar" },
             { name: "Retorno futuro", description: "Acompanhar depois", stage_type: "open" }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(external_stage.reload.name).to eq("Status externo")
    expect(pipeline.stages.find_by!(name: "Retorno futuro")).to be_present
  end

  it "renomeia etapa mantendo os leads vinculados reconciliados" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    stage = pipeline.stages.create!(tenant: admin.tenant, name: "Visita")
    lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

    post bulk_update_admin_lead_statuses_path,
         params: {
           lead_pipeline_id: pipeline.id,
           statuses: [
             { id: stage.id, name: "Visita confirmada", description: "Etapa validada", stage_type: "open" }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(stage.reload.name).to eq("Visita confirmada")
    expect(lead.reload).to have_attributes(lead_pipeline_stage_id: stage.id, status: "Visita confirmada")
  end

  it "remove etapa transferindo leads para a primeira etapa restante do mesmo funil" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    fallback_stage = pipeline.stages.order(:position).first
    stage = pipeline.stages.create!(tenant: admin.tenant, name: "Descartar depois", position: 99)
    lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

    post bulk_update_admin_lead_statuses_path,
         params: {
           lead_pipeline_id: pipeline.id,
           statuses: [
             { id: stage.id, name: stage.name, _destroy: "1" }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(pipeline.stages.find_by(id: stage.id)).to be_nil
    expect(lead.reload).to have_attributes(lead_pipeline_stage_id: fallback_stage.id, status: fallback_stage.name)
  end
end
