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

  it "exibe a documentacao didatica do modal de funil e etapas" do
    get documentation_admin_lead_statuses_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Guia de funis e etapas")
    expect(response.body).to include("Pesquisar nesta documentação")
    expect(response.body).to include("Qualificação no card")
    expect(response.body).to include("Fila de divergência")
    expect(response.body).to include("data-controller=\"doc-search\"")
    expect(Nokogiri::HTML(response.body).css("details.ax-documentation__section[open]")).to be_empty
  end

  it "exibe a auditoria das execuções de automações de etapa com filtros" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    stage = pipeline.stages.create!(tenant: admin.tenant, name: "Sem retorno")
    automation = create(
      :lead_pipeline_stage_automation,
      tenant: admin.tenant,
      lead_pipeline_stage: stage,
      auto_advance_to_stage: nil,
      action_type: "create_task"
    )
    lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name, name: "Lead Auditado")
    create(
      :lead_pipeline_stage_automation_execution,
      tenant: admin.tenant,
      lead_pipeline_stage_automation: automation,
      lead: lead,
      lead_pipeline_stage: stage,
      action_type: "create_task",
      status: "succeeded"
    )
    external_pipeline = LeadPipeline.ensure_default!(tenant: other_tenant)
    external_stage = external_pipeline.stages.create!(tenant: other_tenant, name: "Externa")
    external_automation = create(:lead_pipeline_stage_automation, tenant: other_tenant, lead_pipeline_stage: external_stage)
    external_lead = create(:lead, tenant: other_tenant, lead_pipeline: external_pipeline, lead_pipeline_stage: external_stage, status: external_stage.name, name: "Lead Externo")
    create(:lead_pipeline_stage_automation_execution, tenant: other_tenant, lead_pipeline_stage_automation: external_automation, lead: external_lead, lead_pipeline_stage: external_stage)

    get automation_executions_admin_lead_statuses_path(action_type: "create_task", status: "succeeded", q: "Auditado")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Auditoria das automações")
    expect(response.body).to include("Lead Auditado")
    expect(response.body).to include("Criar tarefa")
    expect(response.body).to include("Concluída")
    expect(response.body).not_to include("Lead Externo")
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

  it "salva politica operacional, proximas etapas e acao final" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    source_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Triagem")
    destination_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Atendimento")
    archive_reason = admin.tenant.attribute_options.create!(
      context: "lead",
      category: "archive_reason",
      name: "Sem potencial"
    )

    post bulk_update_admin_lead_statuses_path,
         params: {
           lead_pipeline_id: pipeline.id,
           statuses: [
             {
               id: source_stage.id,
               name: source_stage.name,
               stage_type: "open",
               color: "#8a63d2",
               active: "1",
               next_stage_ids: [destination_stage.id],
               policy: {
                 visible_to_roles: %w[broker manager],
                 divergence_queue_enabled: "1",
                 future_activity_limit_days: "7",
                 qualification_enabled: "1",
                 qualification_options: %w[qualified missing_data],
                 allowed_archive_reason_ids: [archive_reason.id]
               },
               automations: [
                 {
                   active: "1",
                   trigger: "stage_duration",
                   after_amount: "3",
                   after_unit: "days",
                   action_type: "archive_lead",
                   action_config: { archive_reason_id: archive_reason.id, note: "Sem retorno" }
                 }
               ]
             }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(source_stage.reload.next_stages).to contain_exactly(destination_stage)
    expect(source_stage.color).to eq("#8a63d2")
    expect(source_stage.policy).to have_attributes(
      visible_to_roles: %w[broker manager],
      divergence_queue_enabled: true,
      future_activity_limit_days: 7,
      qualification_enabled: true,
      qualification_options: %w[qualified missing_data],
      allowed_archive_reason_ids: [archive_reason.id]
    )
    expect(source_stage.automations.last).to have_attributes(
      action_type: "archive_lead",
      action_config: hash_including("archive_reason_id" => archive_reason.id.to_s, "note" => "Sem retorno")
    )
  end

  it "salva limite de tentativas sem sucesso na automacao da etapa" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    source_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Atendimento")
    destination_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Segunda tentativa")

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
                   after_amount: "7",
                   after_unit: "days",
                   auto_advance_to_stage_id: destination_stage.id,
                   action_type: "redistribute_lead",
                   action_config: { unsuccessful_attempt_limit: "10", note: "Sem sucesso no primeiro atendimento" }
                 }
               ]
             }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(source_stage.reload.automations.last).to have_attributes(
      action_type: "redistribute_lead",
      auto_advance_to_stage_id: destination_stage.id,
      action_config: hash_including("unsuccessful_attempt_limit" => 10, "note" => "Sem sucesso no primeiro atendimento")
    )
  end

  it "bloqueia movimentacao fora das proximas etapas permitidas" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    source_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Triagem")
    allowed_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Atendimento")
    blocked_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Perdido manual", stage_type: "lost")
    create(:lead_pipeline_stage_transition, lead_pipeline_stage: source_stage, tenant: admin.tenant, next_stage: allowed_stage)
    lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)

    patch admin_lead_path(lead),
          params: {
            lead: {
              lead_pipeline_id: pipeline.id,
              lead_pipeline_stage_id: blocked_stage.id
            }
          },
          headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.lead_pipeline_stage_id).to eq(source_stage.id)
  end

  it "bloqueia etapa de destino invisivel para o perfil do usuario" do
    manager_profile = admin.tenant.profiles.find_or_create_by!(key: "gerente") do |profile|
      profile.name = "Gerente"
      profile.axis = "vertical"
      profile.permissions = Profile.default_permissions_for("Gerente")
    end
    manager = create(:admin_user, email: "manager-#{SecureRandom.hex(6)}@salute.test", tenant: admin.tenant, profile: manager_profile)
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    source_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Triagem")
    hidden_stage = pipeline.stages.create!(tenant: admin.tenant, name: "Gestão")
    create(:lead_pipeline_stage_policy, lead_pipeline_stage: hidden_stage, tenant: admin.tenant, visible_to_roles: %w[broker admin])
    lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name, admin_user: manager)

    sign_out admin
    sign_in manager

    patch admin_lead_path(lead),
          params: {
            lead: {
              lead_pipeline_id: pipeline.id,
              lead_pipeline_stage_id: hidden_stage.id
            }
          },
          headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.lead_pipeline_stage_id).to eq(source_stage.id)
  end

  it "bloqueia remocao de etapa com leads sem informar etapa de destino" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
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

    expect(response).to have_http_status(:unprocessable_entity)
    payload = JSON.parse(response.body)
    expect(payload["error"]).to include("Escolha para qual etapa enviar os leads")
    expect(stage.reload).to be_present
    expect(lead.reload).to have_attributes(lead_pipeline_stage_id: stage.id, status: stage.name)
  end

  it "remove etapa transferindo leads para a etapa escolhida" do
    pipeline = LeadPipeline.ensure_default!(tenant: admin.tenant)
    stage = pipeline.stages.create!(tenant: admin.tenant, name: "Descartar depois", position: 99)
    replacement_stage = pipeline.stages.where.not(id: stage.id).ordered.first
    lead = create(:lead, tenant: admin.tenant, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)

    post bulk_update_admin_lead_statuses_path,
         params: {
           lead_pipeline_id: pipeline.id,
           statuses: [
             { id: stage.id, name: stage.name, replacement_stage_id: replacement_stage.id, _destroy: "1" }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(pipeline.stages.find_by(id: stage.id)).to be_nil
    expect(lead.reload).to have_attributes(lead_pipeline_stage_id: replacement_stage.id, status: replacement_stage.name)
  end
end
