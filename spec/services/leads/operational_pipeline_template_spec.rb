require "rails_helper"

RSpec.describe Leads::OperationalPipelineTemplate do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { Tenant.create!(name: "Template #{SecureRandom.hex(3)}", slug: "template-#{SecureRandom.hex(3)}") }

  after { travel_back }

  it "cria o funil operacional inicial com etapas, politicas, motivos e transicoes" do
    pipeline = described_class.apply!(tenant: tenant)

    expect(pipeline).to have_attributes(
      name: "Principal",
      kind: "mixed",
      default_general: true,
      default_for_sale: true,
      default_for_rental: true
    )
    expect(pipeline.stages.ordered.pluck(:name, :stage_type)).to eq(
      [
        ["Novo Lead", "open"],
        ["Em Atendimento", "open"],
        ["Visita/Contato", "open"],
        ["Proposta", "open"],
        ["Ganho", "won"],
        ["Perdido", "lost"],
        ["Arquivado", "archived"]
      ]
    )
    expect(tenant.attribute_options.for_context("lead").for_category("archive_reason").count)
      .to eq(described_class::ARCHIVE_REASON_NAMES.size)

    novo = pipeline.stages.find_by!(name: "Novo Lead")
    proposta = pipeline.stages.find_by!(name: "Proposta")
    perdido = pipeline.stages.find_by!(name: "Perdido")
    arquivado = pipeline.stages.find_by!(name: "Arquivado")

    expect(novo.next_stages.pluck(:name)).to eq(["Em Atendimento"])
    expect(proposta.next_stages.order(:name).pluck(:name)).to contain_exactly("Em Atendimento", "Ganho", "Perdido", "Arquivado")
    expect(perdido.policy).to have_attributes(divergence_queue_enabled: true, qualification_enabled: true)
    expect(arquivado.policy.visible_to_roles).to eq(%w[manager administrative admin])
    expect(novo.policy.allowed_archive_reason_ids.size).to eq(described_class::ARCHIVE_REASON_NAMES.size)
    expect(pipeline.stages.joins(:automations).distinct.count).to eq(5)
    expect(pipeline.stages.flat_map(&:automations)).to all(have_attributes(active: false))
  end

  it "e idempotente quando aplicado novamente no mesmo funil" do
    pipeline = described_class.apply!(tenant: tenant)

    expect {
      described_class.apply!(tenant: tenant, pipeline: pipeline)
    }.not_to change { [
      tenant.lead_pipelines.count,
      tenant.lead_pipeline_stages.count,
      tenant.lead_pipeline_stage_transitions.count,
      tenant.lead_pipeline_stage_automations.count,
      tenant.attribute_options.for_context("lead").for_category("archive_reason").count
    ] }
  end

  it "reaproveita etapas existentes com nomes equivalentes sem diferenciar maiusculas" do
    pipeline = LeadPipeline.default_for(tenant: tenant)
    existing_stage = pipeline.stages.find_by!(name: "Novo Lead")
    existing_stage.update!(name: "Novo lead", color: "#111111")
    lead = create(
      :lead,
      tenant: tenant,
      lead_pipeline: pipeline,
      lead_pipeline_stage: existing_stage,
      status: "Novo lead"
    )

    expect {
      described_class.apply!(tenant: tenant, pipeline: pipeline)
    }.not_to raise_error

    expect(pipeline.stages.where("LOWER(name) = ?", "novo lead").count).to eq(1)
    expect(existing_stage.reload).to have_attributes(name: "Novo Lead", color: "#2f80a0", position: 0)
    expect(lead.reload.status).to eq("Novo Lead")
  end

  it "valida com tempos curtos que um lead consegue passar por todas as etapas do template" do
    travel_to Time.zone.local(2026, 8, 22, 9, 0, 0)
    pipeline = described_class.apply!(
      tenant: tenant,
      automation_active: true,
      automation_after_amount: 1,
      automation_after_unit: "minutes",
      validation_chain: true
    )
    stages = pipeline.stages.ordered.index_by(&:name)
    lead = create(
      :lead,
      tenant: tenant,
      lead_pipeline: pipeline,
      lead_pipeline_stage: stages.fetch("Novo Lead"),
      status: "Novo Lead",
      created_at: 2.minutes.ago,
      updated_at: 2.minutes.ago
    )

    visited_stage_names = [lead.lead_pipeline_stage.name]

    described_class::VALIDATION_CHAIN.each do |_from_stage, to_stage|
      Leads::PipelineStageAutoAdvanceService.call(tenant: tenant)
      lead.reload
      visited_stage_names << lead.lead_pipeline_stage.name
      expect(lead.lead_pipeline_stage.name).to eq(to_stage)
      travel 2.minutes
    end

    expect(visited_stage_names).to eq([
      "Novo Lead",
      "Em Atendimento",
      "Visita/Contato",
      "Proposta",
      "Ganho",
      "Perdido",
      "Arquivado"
    ])
    expect(LeadPipelineStageAutomationExecution.where(tenant: tenant, lead: lead).succeeded.count).to eq(6)
    expect(lead.activities.where(kind: "status_change").count).to eq(6)
  end
end
