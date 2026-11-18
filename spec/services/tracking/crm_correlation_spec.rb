require "rails_helper"

RSpec.describe "Correlação dos marcos do CRM" do
  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant, kind: "sale") }
  let(:stage) do
    create(:lead_pipeline_stage, lead_pipeline: pipeline, google_event: "qualify_lead", google_event_trigger: "qualified",
      meta_conversion_event: "QualifiedLead", meta_event_trigger: "qualified")
  end
  let(:lead) do
    create(:lead, tenant: tenant, admin_user: owner, email: "original@example.test", lead_pipeline: pipeline,
      lead_pipeline_stage: stage, status: stage.name, attribution_channel: "meta_ads", skip_automatic_routing: true,
      attribution_data: { "business_type" => "sale", "analytics_consent" => "granted", "client_id" => "123.456" })
  end

  before do
    WebhookSetting.create!(tenant: tenant, enabled: true, google_conversions_enabled: true, webhook_url: "https://gtm.example.test/events")
    Ga4ConversionConfig.create!(tenant: tenant, enabled: true, activated_at: 1.hour.ago, measurement_id: "G-TEST123", api_secret: "secret")
    MetaConversionConfig.create!(tenant: tenant, datasets: [{ "id" => "999" }])
    create(:user_meta_integration, admin_user: owner, tenant: tenant, access_token: "token")
    allow(HTTParty).to receive(:post) { raise "HTTP proibido neste teste" }
    lead.skip_automatic_routing = false
  end

  it "liga qualificação a GA4, Google e Meta sem alterar IDs, payloads ou deduplicação" do
    lead.skip_automatic_routing = false
    lead.update!(broker_qualification_status: "qualified")
    links = lead.tracking_event_links.to_a
    expect(links.map(&:transport)).to match_array(%w[ga4 google_webhook meta])
    expect(links.map(&:occurrence_key).uniq).to eq([Tracking::Correlation.change(lead)[:occurrence_key]])
    google = GoogleStageConversionEvent.find_by!(lead_id: lead.id)
    ga4 = Ga4ConversionEvent.find_by!(lead_id: lead.id)
    expect(links.find { |row| row.transport == "google_webhook" }.external_event_id).to eq("#{lead.id}_qualificado")
    expect(google.payload_data).to include("event_id" => "#{lead.id}_qualificado", "transaction_id" => "#{lead.id}_qualificado")
    expect(links.find { |row| row.transport == "ga4" }.external_event_id).to eq(ga4.event_id)
    expect(links.find { |row| row.transport == "meta" }.external_event_id).to eq(Meta::ConversionDispatcher.event_id(tenant.id, lead.id, "QualifiedLead"))
    expect(google.payload_data).not_to have_key("correlation_id")
    expect(ga4.parameters.keys).to match_array(Ga4ConversionEvent::PARAMETER_KEYS)

    google.update!(status: "delivered", attempt_log: [{ "http_status" => 200 }])
    ga4.update!(status: "uncertain", attempted_at: Time.current)
    expect(links.find { |row| row.transport == "google_webhook" }.reload.delivery_status).to eq("http_accepted")
    expect(links.find { |row| row.transport == "ga4" }.reload.delivery_status).to eq("uncertain")
    expect { lead.update!(manager_qualification_status: "qualified") }.not_to change(TrackingEventLink, :count)
  end

  it "distingue visitas diferentes sem trocar a identidade legada do Google ou da Meta" do
    stage.update!(google_event: "visit", google_event_trigger: "visit_completed",
      meta_conversion_event: "Schedule", meta_event_trigger: "visit_completed")
    visits = 2.times.map { create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: "visita") }
    visits.each { |visit| visit.update!(status: "realizado") }
    ga4_links = lead.tracking_event_links.where(transport: "ga4")
    expect(ga4_links.count).to eq(2)
    expect(ga4_links.pluck(:occurrence_key)).to match_array(visits.map { |visit| Tracking::Correlation.change(visit)[:occurrence_key] })
    legacy = lead.tracking_event_links.where(transport: "google_webhook").sole
    expect(legacy.external_event_id).to eq("#{lead.id}_visita")
    expect(legacy.occurrence_key).to eq(Tracking::Correlation.change(visits.first)[:occurrence_key])
    expect(lead.tracking_event_links.where(transport: "meta").count).to eq(1)
  end

  it "usa a proposta como ocorrência e não muda o marco ao visualizar ou aceitar" do
    stage.update!(google_event: "proposal", google_event_trigger: "proposal_sent",
      meta_conversion_event: "SubmitApplication", meta_event_trigger: "proposal_sent")
    proposal = Proposal.create!(lead: lead, admin_user: owner, status: "rascunho")
    proposal.mark_sent!
    expect(lead.tracking_event_links.pluck(:occurrence_key).uniq).to eq([Tracking::Correlation.change(proposal)[:occurrence_key]])
    expect(lead.tracking_event_links.count).to eq(3)
    expect { proposal.mark_viewed!; proposal.decide!("aceita") }.not_to change(TrackingEventLink, :count)
  end

  it "reverte correlação junto com o domínio, sem entrega Meta antes do commit" do
    lead.skip_automatic_routing = false
    expect do
      Lead.transaction(requires_new: true) do
        lead.update!(broker_qualification_status: "qualified")
        raise ActiveRecord::Rollback
      end
    end.not_to change(TrackingEventLink, :count)
    expect(GoogleStageConversionEvent.where(lead_id: lead.id)).not_to exist
    expect(Ga4ConversionEvent.where(lead_id: lead.id)).not_to exist
  end
end
