require "rails_helper"

RSpec.describe "Qualificação e fechamento por corretor em configuração antiga", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:tenant) { Tenant.default }
  let(:profile) { Profile.create!(tenant: tenant, name: "Corretor legado", axis: "vertical", permissions: {"leads" => {"view" => true, "edit" => true, "scope" => "own"}, "comercial" => {"view" => true, "manage" => true, "scope" => "own"}}) }
  let(:broker) { create(:admin_user, tenant: tenant, profile: profile) }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant, kind: "rental") }
  let(:stage) { create(:lead_pipeline_stage, lead_pipeline: pipeline, name: "Atendimento legado", google_event: "qualify_lead", google_event_trigger: "qualified") }
  let(:won) { create(:lead_pipeline_stage, lead_pipeline: pipeline, name: "Fechamento legado", stage_type: "won", google_event: "closed", google_event_trigger: "deal_closed") }
  let!(:lead) { create(:lead, tenant: tenant, admin_user: broker, email: "legacy@example.test", lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name) }

  before do
    host! "localhost"
    stage.policy.update_columns(qualification_enabled: false, qualification_options: ["disqualified"])
    won
    WebhookSetting.create!(tenant: tenant, enabled: true, google_conversions_enabled: true, webhook_url: "https://example.test/conversions")
    allow_any_instance_of(GoogleStageConversionEvent).to receive(:enqueue_delivery)
    allow(HTTParty).to receive(:post) { raise "Envio externo proibido neste teste" }
    sign_in broker
  end

  it "exibe, aceita e registra a qualificação e o fechamento sem duplicar nem mudar a configuração" do
    get admin_leads_path(view: "kanban")
    card = Nokogiri::HTML(response.body).at_css("#lead_#{lead.id}")
    expect(card.css('button').map(&:text).map(&:strip)).to include("Qualificado", "Desqualificado")
    patch admin_lead_path(lead), params: {lead: {broker_qualification_status: "qualified"}}
    expect(lead.reload.broker_qualification_status).to eq("qualified")
    qualified = GoogleStageConversionEvent.find_by!(tenant: tenant, lead: lead, conversion_type: "qualificado")
    expect(qualified.payload_data).to include("event_name" => "qualify_lead", "business_type" => "aluguel")
    expect(qualified.status).to eq("pending")
    expect(stage.policy.reload.qualification_enabled?).to be(false)
    expect { patch admin_lead_path(lead), params: {lead: {broker_qualification_status: "qualified"}} }.not_to change(GoogleStageConversionEvent, :count)
    get admin_lead_path(lead)
    fields = Nokogiri::HTML(response.body).css('select[name="lead[lead_pipeline_stage_id]"]')
    expect(fields.flat_map { |field| field.css('option').map { |option| option['value'] } }.reject(&:blank?).uniq).to eq([won.id.to_s])
    post close_deal_admin_lead_path(lead), params: {lead: {lead_pipeline_stage_id: won.id, closing_commission: "125,50"}}
    expect(lead.reload).to have_attributes(lead_pipeline_stage_id: won.id, closing_commission_cents: 12550)
    closed = GoogleStageConversionEvent.find_by!(tenant: tenant, lead: lead, conversion_type: "fechamento")
    expect(closed.payload_data).to include("event_name" => "close_convert_lead", "value" => 125.5, "currency" => "BRL")
    expect(closed.status).to eq("pending")
    expect { post close_deal_admin_lead_path(lead), params: {lead: {lead_pipeline_stage_id: won.id}} }.not_to change(GoogleStageConversionEvent, :count)
  end

  it "não aceita avaliar ou fechar lead de outra conta" do
    other = Tenant.create!(name: "Outra conta legado", slug: "other-legacy-#{SecureRandom.hex(4)}")
    outsider = create(:lead, tenant: other, skip_automatic_routing: true)
    sign_in broker
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    patch admin_lead_path(outsider, format: :json), params: {lead: {broker_qualification_status: "qualified"}}
    expect(response).to have_http_status(:not_found)
    post close_deal_admin_lead_path(outsider, format: :json), params: {lead: {lead_pipeline_stage_id: won.id}}
    expect(response).to have_http_status(:not_found)
    expect(outsider.reload.broker_qualification_status).to be_nil
  end
end
