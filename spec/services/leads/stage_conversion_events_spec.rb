require "rails_helper"

RSpec.describe Leads::StageConversionEvents do
  let(:tenant) { Tenant.default }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant, kind: "sale") }
  let(:stage) { create(:lead_pipeline_stage, lead_pipeline: pipeline, name: "Em Atendimento", google_event: "qualify_lead", google_event_trigger: "qualified") }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: owner, email: "original@example.test", lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name) }
  let!(:setting) { WebhookSetting.create!(tenant: tenant, enabled: true, google_conversions_enabled: true, webhook_url: "https://gtm.example.test/events") }

  before do
    allow(HTTParty).to receive(:post) { raise "HTTP proibido neste teste" }
    allow_any_instance_of(GoogleStageConversionEvent).to receive(:enqueue_delivery)
    lead.update_column(:google_business_type, "venda")
  end

  it "aguarda a ação configurada, sem inferir qualificação pelo nome ou entrada" do
    lead.update!(notes: "Primeiro atendimento")
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
    lead.update!(broker_qualification_status: "qualified")
    expect(GoogleStageConversionEvent.where(tenant: tenant).pluck(:conversion_type)).to eq(["qualificado"])
    lead.update!(manager_qualification_status: "qualified")
    expect(GoogleStageConversionEvent.where(tenant: tenant).count).to eq(1)
  end

  it "respeita funis diferentes da mesma conta e não muda inscrições globais" do
    setting.update!(subscribed_events: WebhookSetting::DEFAULT_EVENTS + ["qualified_lead"])
    other_pipeline = create(:lead_pipeline, tenant: tenant)
    other_stage = create(:lead_pipeline_stage, lead_pipeline: other_pipeline, name: stage.name)
    other = create(:lead, tenant: tenant, admin_user: owner, lead_pipeline: other_pipeline, lead_pipeline_stage: other_stage, status: other_stage.name)
    other.update!(broker_qualification_status: "qualified")
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
    lead.update!(broker_qualification_status: "qualified")
    expect(GoogleStageConversionEvent.where(tenant: tenant).pluck(:lead_id)).to eq([lead.id])
    expect(setting.reload.subscribed_events).to include("qualified_lead")
  end

  it "só registra visita quando um compromisso de visita é realizado na etapa configurada" do
    stage.update!(google_event: "visit", google_event_trigger: "visit_completed")
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: owner)
    appointment.update!(notes: "Agendada")
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
    appointment.update!(status: "realizado")
    event = GoogleStageConversionEvent.where(tenant: tenant).sole
    expect(event.conversion_type).to eq("visita")
    expect(event.occurred_at).to be_within(1.second).of(appointment.updated_at)
    appointment.update!(notes: "Acompanhamento")
    expect(GoogleStageConversionEvent.where(tenant: tenant).count).to eq(1)
  end

  it "ignora reunião realizada, etapa sem evento e integração pausada" do
    stage.update!(google_event: "visit", google_event_trigger: "visit_completed")
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: "reuniao").update!(status: "realizado")
    setting.update!(google_conversions_enabled: false)
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner).update!(status: "realizado")
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
  end

  it "registra proposta somente ao enviar e não ao aceitar" do
    stage.update!(google_event: "proposal", google_event_trigger: "proposal_sent")
    proposal = Proposal.create!(lead: lead, admin_user: owner, status: "rascunho")
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
    proposal.update!(status: "enviada")
    expect(GoogleStageConversionEvent.where(tenant: tenant).pluck(:conversion_type)).to eq(["proposta"])
    proposal.update!(status: "aceita")
    expect(GoogleStageConversionEvent.where(tenant: tenant).count).to eq(1)
  end

  it "registra fechamento pela conclusão em etapa ganha, sem eventos fixos em outras etapas" do
    stage.update!(google_event: "closed", google_event_trigger: "deal_closed", stage_type: "won")
    lead.update!(status: stage.name, notes: "Não é uma transição")
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
    initial = create(:lead_pipeline_stage, lead_pipeline: pipeline)
    lead.update!(lead_pipeline_stage: initial, status: initial.name)
    lead.update!(lead_pipeline_stage: stage, status: stage.name, closing_commission: "100,00")
    expect(GoogleStageConversionEvent.where(tenant: tenant).sole.payload_data).to include("event_name" => "close_convert_lead", "value" => 100.0)
  end

  it "não registra evento de etapa inativa, outra conta ou importação suprimida" do
    stage.update!(active: false)
    described_class.dispatch(lead, ["qualified"], provider: :google)
    stage.update!(active: true)
    lead.skip_automatic_routing = true
    described_class.dispatch(lead, ["qualified"], provider: :google)
    lead.skip_automatic_routing = false
    other = Tenant.create!(name: "Outra conversão", slug: "other-stage-conversion")
    other_pipeline = create(:lead_pipeline, tenant: other)
    foreign_stage = create(:lead_pipeline_stage, lead_pipeline: other_pipeline, google_event: "qualify_lead", google_event_trigger: "qualified")
    lead.lead_pipeline_stage_id = foreign_stage.id
    described_class.dispatch(lead, ["qualified"], provider: :google)
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
  end

  it "não mantém outbox nem agenda Meta quando a transação comercial reverte" do
    stage.update!(meta_conversion_event: "QualifiedLead", meta_event_trigger: "qualified")
    allow(Meta::ConversionDispatcher).to receive(:call)
    Lead.transaction(requires_new: true) do
      lead.update!(broker_qualification_status: "qualified")
      raise ActiveRecord::Rollback
    end
    expect(GoogleStageConversionEvent.where(tenant: tenant)).to be_empty
    expect(Meta::ConversionDispatcher).not_to have_received(:call)
  end

  it "rejeita combinação incompatível entre evento e ação Google" do
    stage.google_event_trigger = "visit_completed"
    expect(stage).not_to be_valid
    expect(stage.errors[:google_event_trigger]).to be_present
  end

  it "permite ações Meta configuradas sem atrelar significado ao nome da etapa" do
    stage.update!(meta_conversion_event: "QualifiedLead", meta_event_trigger: "qualified")
    allow(Meta::ConversionDispatcher).to receive(:call)
    described_class.dispatch(lead, ["stage_entered"], provider: :meta)
    expect(Meta::ConversionDispatcher).not_to have_received(:call)
    described_class.dispatch(lead, ["qualified"], provider: :meta)
    expect(Meta::ConversionDispatcher).to have_received(:call).with(hash_including(lead: lead, event_name: "QualifiedLead"))
  end
end
