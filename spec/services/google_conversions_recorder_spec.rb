require "rails_helper"

RSpec.describe GoogleConversions::Recorder do
  around do |example|
    previous = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous
  end

  let(:setting) { WebhookSetting.create!(tenant: Current.tenant, webhook_url: "https://gtm.example.com/events", enabled: true, google_conversions_enabled: true) }
  let(:lead) { create(:lead, name: "Maria Silva", email: "original@example.com", other_information: { attribution: { business_type: "sale" } }) }

  before do
    allow_any_instance_of(GoogleStageConversionEvent).to receive(:enqueue_delivery)
    lead.update_column(:google_business_type, "venda")
  end

  it "inclui o UID inicial nos três nomes de conversão e omite quando ausente" do
    lead.update!(attribution_data: { "tracking_uid" => "UID_Ab%2F+", "utm_content" => "outra-campanha" })
    %w[qualify_lead visit proposal closed].each do |event|
      described_class.record(lead, setting, event)
    end
    GoogleStageConversionEvent.where(lead_id: lead.id).each do |event|
      expect(event.payload_data["utm_content"]).to eq("UID_Ab%2F+")
      expect(event.payload_data.dig("source", "utm", "utm_content")).to eq("UID_Ab%2F+")
    end
  end

  it "usa a identidade original e registra cada tipo uma única vez" do
    lead.update!(email: "edited@example.com")
    2.times { described_class.record(lead, setting, "visit") }
    event = GoogleStageConversionEvent.find_by!(lead_id: lead.id)
    expect(GoogleStageConversionEvent.where(lead_id: lead.id).count).to eq(1)
    expect(event.payload_data).to include("event_name" => "working_lead", "transaction_id" => "#{lead.id}_visita", "business_type" => "venda", "diagnostic" => true)
    expect(event.payload_data.dig("user_data", "email_address")).to eq("original@example.com")
    expect(event.payload_before_type_cast).not_to include("original@example.com")
  end

  it "envia somente a comissão real no fechamento e mantém o primeiro retrato" do
    lead.update!(closing_commission: "1.234,56")
    described_class.record(lead, setting, "closed")
    lead.update!(closing_commission: "9.000,00")
    described_class.record(lead, setting, "closed")
    payload = GoogleStageConversionEvent.find_by!(lead_id: lead.id).payload_data
    expect(payload).to include("value" => 1234.56, "currency" => "BRL")
    expect(payload).not_to have_key("lead_status")
    expect(payload.keys).not_to include("utm_content", "source")
  end

  it "omite valor e moeda quando não há comissão e em eventos intermediários" do
    described_class.record(lead, setting, "closed")
    lead.update!(closing_commission: "100,00")
    described_class.record(lead, setting, "proposal")
    GoogleStageConversionEvent.where(lead_id: lead.id).each do |event|
      expect(event.payload_data.keys).not_to include("value", "currency")
    end
  end

  it "não usa o e-mail editado quando falta a identidade de criação" do
    allow(lead.lead_audit_logs).to receive(:where).and_return(LeadAuditLog.none)
    described_class.record(lead, setting, "visit")
    expect(GoogleStageConversionEvent.find_by!(lead_id: lead.id)).to have_attributes(status: "skipped", skip_reason: "original_email_missing")
  end
  it "captura a entrada na etapa configurada, não a simples edição do lead" do
    setting
    pipeline = create(:lead_pipeline, kind: "sale")
    initial = create(:lead_pipeline_stage, lead_pipeline: pipeline)
    visit = create(:lead_pipeline_stage, lead_pipeline: pipeline, google_event: "visit")
    lead.update!(lead_pipeline: pipeline, lead_pipeline_stage: initial, status: initial.name)
    expect { lead.update!(lead_pipeline_stage: visit, status: visit.name) }.to change { GoogleStageConversionEvent.where(lead_id: lead.id).count }.by(1)
    expect { lead.update!(notes: "Atualização") }.not_to change(GoogleStageConversionEvent, :count)
    lead.update!(lead_pipeline_stage: initial, status: initial.name)
    expect { lead.update!(lead_pipeline_stage: visit, status: visit.name) }.not_to change(GoogleStageConversionEvent, :count)
  end

  it "mantém os eventos de entrada e desmarca a qualificação por avaliação quando há etapa mapeada" do
    setting.update!(subscribed_events: WebhookSetting::DEFAULT_EVENTS + ["qualified_lead"])
    pipeline = create(:lead_pipeline)
    create(:lead_pipeline_stage, lead_pipeline: pipeline, google_event: "qualify_lead")
    expect(setting.reload.subscribed_events).to eq(WebhookSetting::DEFAULT_EVENTS)
    expect(WebhookSetting.new.google_conversions_enabled).to be(false)
    expect(build(:lead_pipeline_stage).google_event).to eq("none")
  end

  it "não permite dois destinos Google na mesma conta" do
    setting
    duplicate = WebhookSetting.new(tenant: Current.tenant, webhook_url: "https://other.example.com", google_conversions_enabled: true)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:tenant_id]).to be_present
  end

  it "deduplica a qualificação por avaliação, inclusive entre corretor e gestor" do
    setting.update!(subscribed_events: WebhookSetting::DEFAULT_EVENTS + ["qualified_lead"])
    lead.update!(broker_qualification_status: "qualified")
    lead.update!(manager_qualification_status: "qualified")
    lead.update!(broker_qualification_status: "disqualified")
    lead.update!(broker_qualification_status: "qualified")
    expect(GoogleStageConversionEvent.where(lead_id: lead.id).pluck(:conversion_type)).to eq(["qualificado"])
  end

  it "não registra alterações de importação nem usa o destino de outra conta" do
    setting
    lead.skip_automatic_routing = true
    lead.update!(manager_qualification_status: "qualified")
    expect(GoogleStageConversionEvent.where(lead_id: lead.id)).not_to exist
    other = Tenant.create!(name: "Outra conta", slug: "google-isolated-#{SecureRandom.hex(4)}")
    foreign_lead = create(:lead, tenant: other)
    foreign_lead.update!(manager_qualification_status: "qualified")
    expect(GoogleStageConversionEvent.where(lead_id: foreign_lead.id)).not_to exist
  end

end
