require "rails_helper"

RSpec.describe ExternalLeadMigration::FunnelSync do
  let(:tenant) { Tenant.default }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant, name: "Locação", kind: "rental") }

  before { Current.tenant = tenant }

  describe ".mirrored_stage_attributes" do
    let(:integration) { create(:external_lead_integration, tenant:, mirror_c2s_owners: true) }

    it "reconhece o contrato real status e reutiliza as etapas da conta" do
      attendance = create(:lead_pipeline_stage, tenant:, lead_pipeline: pipeline, name: "Em Atendimento | Qualificado")
      visit = create(:lead_pipeline_stage, tenant:, lead_pipeline: pipeline, name: "Agenda | Visita")
      { "In attendance" => attendance, "Scheduled visit" => visit }.each do |name, stage|
        attrs = described_class.mirrored_stage_attributes(integration:, pipeline:,
          payload: { attributes: { funnel_status: { status: name }, lead_status: { alias: "under_negotiation" } } })
        expect(attrs).to include(status: stage.name, lead_pipeline_stage: stage)
      end
    end

    it "prioriza arquivamento sobre uma etapa aberta e não cria novas etapas" do
      archived = create(:lead_pipeline_stage, tenant:, lead_pipeline: pipeline, name: "Desqualificado | Arquivar", stage_type: "archived")
      payload = { attributes: { funnel_status: { status: "In attendance" }, archive_details: { archived: true } } }
      expect {
        attrs = described_class.mirrored_stage_attributes(integration:, pipeline:, payload:)
        expect(attrs[:lead_pipeline_stage]).to eq(archived)
      }.not_to change { tenant.lead_pipeline_stages.count }
    end

    it "não muda a etapa em payload parcial sem estado" do
      expect(described_class.mirrored_stage_attributes(integration:, pipeline:, payload: { attributes: { seller: { id: "1" } } })).to be_nil
    end

    it "respeita o mapeamento existente da conta para o nome externo" do
      custom = create(:lead_pipeline_stage, tenant:, lead_pipeline: pipeline, name: "Acompanhamento personalizado")
      integration.update!(operational_mappings: integration.operational_mappings.merge("stages" => { "em_negociacao" => { "stage_id" => custom.id } }))
      attrs = described_class.mirrored_stage_attributes(integration:, pipeline:,
        payload: { attributes: { funnel_status: { status: "In attendance" }, lead_status: { alias: "under_negotiation", name: "Em negociação" } } })
      expect(attrs[:lead_pipeline_stage]).to eq(custom)
    end
  end

  describe ".status_for!" do
    it "nao recria etapa operacional legada quando ela foi removida do funil" do
      create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Desqualificado | Arquivar")
      payload = { "attributes" => { "lead_status" => { "alias" => "archived" }, "funnel_status" => { "name" => "Descartado" } } }

      expect {
        status = described_class.status_for!(tenant: tenant, payload: payload, pipeline: pipeline)
        expect(status).to eq("Descartado")
      }.not_to change { tenant.lead_pipeline_stages.where(lead_pipeline: pipeline, name: "Descartado").count }
    end

    it "continua criando etapas externas especificas quando nao sao status legados" do
      payload = { "attributes" => { "funnel_status" => { "name" => "Visita agendada" } } }

      expect {
        status = described_class.status_for!(tenant: tenant, payload: payload, pipeline: pipeline)
        expect(status).to eq("Visita agendada")
      }.to change { tenant.lead_pipeline_stages.where(lead_pipeline: pipeline, name: "Visita agendada").count }.by(1)
    end

    it "deixa etapa externa desconhecida cair no padrao quando criacao automatica esta desligada" do
      default_stage = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Novo Lead")
      payload = { "attributes" => { "funnel_status" => { "name" => "Visita agendada" } } }

      expect {
        status = described_class.status_for!(tenant: tenant, payload: payload, pipeline: pipeline, auto_create: false)
        expect(status).to eq(default_stage.name)
      }.not_to change { tenant.lead_pipeline_stages.where(lead_pipeline: pipeline, name: "Visita agendada").count }
    end
  end
end
