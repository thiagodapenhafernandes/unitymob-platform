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

  it "não altera inscrições da conta ao configurar uma etapa" do
    setting.update!(subscribed_events: WebhookSetting::DEFAULT_EVENTS + ["qualified_lead"])
    pipeline = create(:lead_pipeline)
    create(:lead_pipeline_stage, lead_pipeline: pipeline, google_event: "qualify_lead")
    expect(setting.reload.subscribed_events).to eq(WebhookSetting::DEFAULT_EVENTS + ["qualified_lead"])
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
    pipeline = create(:lead_pipeline)
    stage = create(:lead_pipeline_stage, lead_pipeline: pipeline, google_event: "qualify_lead", google_event_trigger: "qualified")
    lead.update!(lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name)
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

  context "com contexto ampliado habilitado apenas na conta" do
    before do
      Setting.set("tracking.structured_events_enabled", "true", tenant: lead.tenant)
      TrackingIntegrationSetting.clear_cache(tenant: lead.tenant)
    end

    it "normaliza locação, mantém IDs e devolve contexto original com data ISO" do
      property = create(:habitation, tenant: lead.tenant, status: "Aluguel", valor_locacao_cents: 490_000)
      lead.update!(property_id: property.id, google_business_type: "aluguel", attribution_data: {
        "tracking_uid" => "UID_Ab%2F+", "utm_source" => "google", "utm_medium" => "cpc",
        "utm_campaign" => "locacao", "analytics_consent" => "granted",
        "client_ip_address" => "192.0.2.1", "client_user_agent" => "Synthetic Browser",
        "landing_url" => "https://example.test/imoveis?email=private@example.test", "fbp" => "fb.1.test"
      })
      described_class.record(lead, setting, "visit", occurred_at: Time.zone.parse("2026-11-08 10:00:00"))
      payload = GoogleStageConversionEvent.where(lead: lead).sole.payload_data
      expect(payload).to include("business_type"=>"locacao", "transaction_id"=>"#{lead.id}_visita",
        "lead_stage"=>"visita_realizada", "property_id"=>property.id.to_s, "property_code"=>property.codigo,
        "property_price"=>4900.0, "utm_source"=>"google", "utm_content"=>"UID_Ab%2F+")
      expect(payload['conversion_datetime']).to include('T')
      expect(payload.dig('user_data','external_id')).to eq(lead.id.to_s)
      expect(payload.dig('visitor','landing_url')).to eq('https://example.test/imoveis')
      expect(payload).not_to have_key('value')
      expect(lead.reload.google_business_type).to eq('aluguel')
    end

    it "aceita telefone original válido sem e-mail e omite dados de navegação sem consentimento" do
      other = create(:lead, email: nil, phone: '+5547991234567', google_business_type: 'venda',
        attribution_data: {'client_ip_address'=>'192.0.2.1','fbp'=>'private-cookie'})
      other.update_column(:google_business_type,'venda')
      described_class.record(other, setting, 'qualify_lead')
      event = GoogleStageConversionEvent.where(lead: other).sole
      expect(event.status).to eq('pending'), {reason:event.skip_reason,payload:event.payload_data}.inspect
      expect(event.payload_data).not_to have_key('visitor')
      expect(event.payload_data.fetch('user_data')).not_to have_key('email_address')
      expect(event.payload_data.dig('user_data','phone_number')).to eq('+5547991234567')
      foreign = Tenant.create!(name:'Outra',slug:"tracking-default-#{SecureRandom.hex(4)}")
      expect(TrackingIntegrationSetting.current(tenant:foreign).structured_events_enabled?).to be(false)
    end
  end

end
