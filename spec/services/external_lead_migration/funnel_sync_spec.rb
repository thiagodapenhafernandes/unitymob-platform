require "rails_helper"

RSpec.describe ExternalLeadMigration::FunnelSync do
  let(:tenant) { Tenant.default }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant, name: "Locação", kind: "rental") }

  before { Current.tenant = tenant }

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
