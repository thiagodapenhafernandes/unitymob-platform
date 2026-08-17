require "rails_helper"

RSpec.describe "Admin::LeadStatuses", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "lead-status-admin-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outro status #{SecureRandom.hex(3)}", slug: "outro-status-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    allow_any_instance_of(Admin::LeadStatusesController).to receive(:verified_request?).and_return(true)
    sign_in admin
  end

  it "lista apenas etapas do funil e tenant atual" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    pipeline.stages.create!(tenant: admin.tenant, name: "Em análise")
    other_current_pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Locação #{SecureRandom.hex(4)}")
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
    stage = pipeline.stages.create!(tenant: admin.tenant, name: "Visita #{SecureRandom.hex(4)}")
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

  it "salva multiplas automacoes de etapa" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    source_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Sem retorno")
    destination_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Nutrição")
    other_pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Pós-venda #{SecureRandom.hex(4)}")
    cross_pipeline_stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: other_pipeline, name: "Reativar")

    post bulk_update_admin_lead_statuses_path,
         params: {
           lead_pipeline_id: pipeline.id,
           statuses: [
             {
               id: source_stage.id,
               name: source_stage.name,
               stage_type: "open",
               automations: [
                 {
                   active: "1",
                   trigger: "customer_inactivity",
                   after_amount: "2",
                   after_unit: "days",
                   auto_advance_to_stage_id: destination_stage.id
                 },
                 {
                   active: "1",
                   trigger: "general_inactivity",
                   after_amount: "4",
                   after_unit: "hours",
                   auto_advance_to_stage_id: cross_pipeline_stage.id
                 }
               ]
             }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    automations = source_stage.reload.automations.ordered
    expect(automations.size).to eq(2)
    expect(automations.first).to have_attributes(
      trigger: "customer_inactivity",
      after_amount: 2,
      after_unit: "days",
      auto_advance_to_stage_id: destination_stage.id
    )
    expect(automations.second).to have_attributes(
      trigger: "general_inactivity",
      after_amount: 4,
      after_unit: "hours",
      auto_advance_to_stage_id: cross_pipeline_stage.id
    )
  end

  it "remove etapa transferindo leads para a primeira etapa restante do mesmo funil" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    stage = pipeline.stages.create!(tenant: admin.tenant, name: "Descartar depois", position: 99)
    fallback_stage = pipeline.stages.where.not(id: stage.id).ordered.first
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
