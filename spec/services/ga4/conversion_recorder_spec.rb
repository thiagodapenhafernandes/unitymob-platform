require "rails_helper"

RSpec.describe Ga4::ConversionRecorder do
  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:lead) do
    create(:lead, tenant: tenant, admin_user: owner, skip_automatic_routing: true,
      attribution_data: { "analytics_consent" => "granted", "client_id" => "123.456", "business_type" => "sale" }).tap do |record|
      record.skip_automatic_routing = false
    end
  end
  let!(:config) { Ga4ConversionConfig.create!(tenant: tenant, enabled: true, activated_at: 1.hour.ago, measurement_id: "G-TEST123", api_secret: "test-secret") }

  before { allow(Ga4ConversionDeliveryJob).to receive(:perform_later) }

  it "qualifica uma vez pelo primeiro corretor ou gestor e não repete ao requalificar" do
    lead.update!(broker_qualification_status: "qualified")
    lead.update!(manager_qualification_status: "qualified")
    lead.update!(broker_qualification_status: "disqualified")
    lead.update!(broker_qualification_status: "qualified")
    expect(Ga4ConversionEvent.where(lead: lead).pluck(:event_name)).to eq(["qualify_lead"])
    expect(Ga4ConversionDeliveryJob).to have_received(:perform_later).once
  end

  it "permite que o gestor confirme primeiro" do
    lead.update!(manager_qualification_status: "qualified")
    expect(Ga4ConversionEvent.where(lead: lead, event_name: "qualify_lead")).to exist
  end

  it "não transforma confirmação posterior do outro papel em qualificação histórica" do
    lead.update_columns(broker_qualification_status: "qualified")
    lead.reload.update!(manager_qualification_status: "qualified")
    expect(Ga4ConversionEvent.where(lead: lead)).not_to exist
  end

  it "falha de registro de telemetria não impede atualização comercial" do
    allow(Ga4ConversionEvent).to receive(:create_or_find_by!).and_raise(ActiveRecord::StatementInvalid, "test failure")
    expect(lead.update(manager_qualification_status: "qualified")).to be(true)
    expect(lead.reload.manager_qualification_status).to eq("qualified")
  end

  it "não registra para conta desativada nem usa a configuração de Current" do
    other = Tenant.create!(name: "Salute isolada", slug: "salute-ga4-#{SecureRandom.hex(4)}")
    other_lead = create(:lead, tenant: other, skip_automatic_routing: true, attribution_data: lead.attribution_data)
    other_lead.skip_automatic_routing = false
    Current.tenant = tenant
    other_lead.update!(broker_qualification_status: "qualified")
    expect(Ga4ConversionEvent.where(lead: other_lead)).not_to exist
    config.update!(enabled: false)
    lead.update!(manager_qualification_status: "qualified")
    expect(Ga4ConversionEvent.where(lead: lead)).not_to exist
  end

  it "não infere consentimento a partir de client_id histórico" do
    lead.update_columns(attribution_data: { "client_id" => "123.456" })
    lead.reload.update!(manager_qualification_status: "qualified")
    expect(Ga4ConversionEvent.where(lead: lead)).not_to exist
  end

  it "ignora alterações sem mudança comercial e cadastros inválidos" do
    lead.update!(name: "Nome atualizado")
    expect(lead.update(manager_qualification_status: "inválido")).to be(false)
    expect(Ga4ConversionEvent.where(lead: lead)).not_to exist
  end

  it "desfaz o evento com rollback sem enfileirar entrega" do
    Lead.transaction do
      lead.update!(manager_qualification_status: "qualified")
      expect(Ga4ConversionEvent.where(lead: lead)).to exist
      raise ActiveRecord::Rollback
    end
    expect(Ga4ConversionEvent.where(lead_id: lead.id)).not_to exist
    expect(Ga4ConversionDeliveryJob).not_to have_received(:perform_later)
  end

  it "distingue visita realizada de agendamento e reunião e deduplica reabertura" do
    visit = create(:appointment, lead: lead, tenant: tenant, admin_user: owner)
    expect(Ga4ConversionEvent.where(lead: lead)).not_to exist
    visit.update!(status: "realizado")
    visit.update!(status: "agendado")
    visit.update!(status: "realizado")
    meeting = create(:appointment, lead: lead, tenant: tenant, admin_user: owner, kind: "reuniao")
    meeting.update!(status: "realizado")
    expect(Ga4ConversionEvent.where(lead: lead).pluck(:event_name)).to eq(["visit_completed"])
    second_visit = create(:appointment, lead: lead, tenant: tenant, admin_user: owner)
    second_visit.update!(status: "realizado")
    expect(Ga4ConversionEvent.where(lead: lead, event_name: "visit_completed").count).to eq(2)
  end

  it "registra proposta enviada, não rascunho ou venda ao aceitar proposta" do
    proposal = Proposal.create!(lead: lead, admin_user: owner, status: "rascunho", title: "Proposta")
    expect(Ga4ConversionEvent.where(lead: lead)).not_to exist
    proposal.mark_sent!
    proposal.mark_sent!
    proposal.decide!("aceita")
    expect(Ga4ConversionEvent.where(lead: lead).pluck(:event_name)).to eq(["proposal_sent"])
  end

  it "registra negócio ganho uma vez, sem declarar compra ou receita" do
    initial = lead.lead_pipeline_stage
    won = lead.lead_pipeline.stages.create!(tenant: tenant, name: "Ganho GA4", stage_type: "won")
    lead.update!(lead_pipeline_stage: won, status: won.name)
    lead.update!(lead_pipeline_stage: initial, status: initial.name)
    lead.update!(lead_pipeline_stage: won, status: won.name)
    expect(Ga4ConversionEvent.where(lead: lead).pluck(:event_name)).to eq(["close_convert_lead"])
    expect(Ga4ConversionEvent.where(lead: lead).first.parameters).not_to have_key("value")
  end

  it "usa somente campos permitidos e cifra client_id e segredo" do
    lead.update!(manager_qualification_status: "qualified")
    event = Ga4ConversionEvent.where(lead: lead).sole
    expect(event.parameters.keys).to match_array(%w[business_type property_code event_id lead_source])
    expect(event.parameters["business_type"]).to eq("venda")
    expect(event.measurement_payload.keys).to match_array(%i[client_id timestamp_micros consent events])
    expect(event.client_id).to eq("123.456")
    expect(event.client_id_before_type_cast).not_to eq("123.456")
    expect(config.api_secret_before_type_cast).not_to eq("test-secret")
  end
end
