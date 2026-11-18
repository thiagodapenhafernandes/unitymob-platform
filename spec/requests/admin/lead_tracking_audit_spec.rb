require "rails_helper"

RSpec.describe "Auditoria de envios do lead", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  let(:context) { Tracking::Correlation.lead_created(lead) }

  def delivery(transport: "meta", event_id: SecureRandom.uuid, destination: "dataset-1")
    Tracking::Correlation.record(context, transport: transport, event_id: event_id, destination: destination)
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "mostra IDs e tentativas escapadas, sem payloads, credenciais ou efeitos de envio" do
    link = delivery(event_id: "original-meta-id")
    Tracking::Correlation.attempt(link, status: "received", trace_id: '<script>alert(1)</script>')
    webhook = delivery(transport: "webhook", event_id: "original-webhook-id", destination: "https://receiver.test/private?token=segredo")
    Tracking::Correlation.attempt(webhook, status: "failed", http_status: 503, error_class: "Timeout::Error")
    expect do
      get tracking_audit_admin_lead_path(lead)
    end.not_to have_enqueued_job
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("original-meta-id", "original-webhook-id", "Recebido pela plataforma", "Falhou", "503", "Timeout::Error")
    expect(response.body).not_to include("token=segredo", "/private", '<script>alert(1)</script>')
    expect(response.body).to include("&lt;script&gt;", "não comprova atribuição", journey_admin_lead_path(lead))
    expect(Nokogiri::HTML(response.body).at_css('.ax-mobile-detail-header')).to be_present
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "projeta os estados nativos Google e GA4 sem exibir seus payloads" do
    google = GoogleStageConversionEvent.create!(tenant: admin.tenant, lead: lead, conversion_type: "visita", status: "delivered",
      occurred_at: Time.current, destination_url: "https://google.test/secret", payload: '{"email":"secret@private.test"}',
      attempt_log: [{ "at" => Time.current.iso8601, "http_status" => 204 }])
    Tracking::Correlation.record(context, transport: "google_webhook", event_id: "google-stable-id", destination: google.destination_url, native_event: google)
    ga4 = Ga4ConversionEvent.create!(tenant: admin.tenant, lead: lead, event_name: "qualify_lead", event_id: "ga4-original-id",
      measurement_id: "G-TEST123", client_id: "123.456", occurred_at: Time.current, deduplication_key: "audit-test",
      status: "uncertain", attempted_at: Time.current, http_status: 500)
    Tracking::Correlation.record(context, transport: "ga4", event_id: ga4.event_id, destination: ga4.measurement_id, native_event: ga4)
    get tracking_audit_admin_lead_path(lead)
    expect(response.body).to include("HTTP aceito", "204", "Sem confirmação", "500", "ga4-original-id", "google-stable-id")
    expect(response.body).not_to include("secret@private.test", "123.456", "https://google.test/secret")
    expect(response.body).to include("apenas o último resultado")
    google.destroy!
    get tracking_audit_admin_lead_path(lead)
    expect(response.body).to include("Registro de envio removido")
  end

  it "filtra por transporte e pagina sem misturar outros leads" do
    26.times { |i| delivery(event_id: "event-#{i}") }
    delivery(transport: "webhook", event_id: "webhook-only", destination: "https://receiver.test")
    other = create(:lead, tenant: admin.tenant, admin_user: admin)
    Tracking::Correlation.record(Tracking::Correlation.lead_created(other), transport: "meta", event_id: "foreign-lead-event", destination: "dataset-1")
    get tracking_audit_admin_lead_path(lead, transport: "meta")
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('div[id^="delivery_tracking_event_link_"]').size).to eq(25)
    expect(response.body).not_to include("webhook-only", "foreign-lead-event", ">event-0<")
    get tracking_audit_admin_lead_path(lead, transport: "meta", page: 2)
    expect(response.body).to include(">event-0<")
    expect(response.body).not_to include("webhook-only")
    get tracking_audit_admin_lead_path(lead, transport: "webhook")
    expect(response.body).to include("webhook-only")
    expect(response.body).not_to include(">event-0<")
  end

  it "explica a ausência de registros e ignora filtros desconhecidos" do
    get tracking_audit_admin_lead_path(lead, transport: "invalid")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nenhum evento correlacionado", "não comprova ausência")
  end

  it "não permite acesso entre contas, mesmo passando tenant_id" do
    other = create(:lead, tenant: Tenant.create!(name: "Outra auditoria", slug: "tracking-other-#{SecureRandom.hex(4)}"))
    get tracking_audit_admin_lead_path(other, tenant_id: other.tenant_id)
    expect(response).to have_http_status(:not_found)
    expect(Nokogiri::HTML(response.body).at_css('section[aria-label="Eventos e envios"]')).to be_nil
  end

  it "reutiliza o escopo próprio do corretor e bloqueia leads fora dele" do
    agent = create(:admin_user, tenant: admin.tenant)
    agent.profile.update!(permissions: { "leads" => { "view" => true, "scope" => "own" } })
    agent.update!(horizontal_profile: nil)
    sign_in agent
    get tracking_audit_admin_lead_path(lead)
    expect(response).to redirect_to(admin_leads_path)
    lead.update_columns(admin_user_id: agent.id)
    get tracking_audit_admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    lead.update_columns(archived_at: Time.current, archived_by_admin_user_id: admin.id)
    get tracking_audit_admin_lead_path(lead)
    expect(response).to redirect_to(admin_leads_path)
    lead.update_columns(archived_at: nil, archived_by_admin_user_id: nil)
    agent.profile.update!(permissions: { "leads" => { "view" => false, "scope" => "own" } })
    get tracking_audit_admin_lead_path(lead)
    expect(response).not_to have_http_status(:ok)
    expect(response.body).not_to include("Eventos e envios")
  end

  it "exige autenticação e oferece o acesso na ficha desktop e mobile" do
    get admin_lead_path(lead)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("a[href='#{tracking_audit_admin_lead_path(lead)}']").size).to eq(2)
    expect(doc.at_css(".lead-pwa-detail a[href='#{tracking_audit_admin_lead_path(lead)}']")).to be_present
    sign_out admin
    get tracking_audit_admin_lead_path(lead)
    expect(response).to redirect_to(new_admin_user_session_path)
  end
end
