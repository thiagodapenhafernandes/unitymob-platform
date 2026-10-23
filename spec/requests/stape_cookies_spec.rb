require "rails_helper"

RSpec.describe "Cookie mestre da Stape", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  before do
    host! "localhost"
    https!
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set("tracking.stape_enabled", "true")
  end

  it "cria identificador anônimo após aceite e renova sem trocar seu valor" do
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"
    get stape_cookie_path
    expect(response).to have_http_status(:no_content)
    uid = cookies[:si_uid]
    expect(uid).to match(/\A[0-9a-f-]{36}\z/)
    header = response.headers["Set-Cookie"].to_s
    expect(header.downcase).to include("secure", "samesite=lax")
    expect(header.downcase).not_to include("httponly")
    expect(response.headers["Cache-Control"]).to include("no-store")
    travel 1.day do
      get stape_cookie_path
      expect(cookies[:si_uid]).to eq(uid)
      expect(response.headers["Set-Cookie"].to_s).to include(400.days.from_now.utc.strftime("%d %b %Y"))
    end
  end

  it "não cria cookie sem aceite e remove um cookie já existente após recusa" do
    get stape_cookie_path
    expect(cookies[:si_uid]).to be_blank
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "rejected"
    cookies[:si_uid] = "existing-id"
    get stape_cookie_path
    expect(cookies[:si_uid]).to be_blank
  end

  it "ignora a configuração de outra conta e não aceita requisição cross-site" do
    other = Tenant.create!(name: "Outra Stape", slug: "cookie-other-#{SecureRandom.hex(4)}")
    other.tenant_domains.create!(hostname: "other-cookie.example.test", primary_domain: true)
    host! "other-cookie.example.test"
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"
    get stape_cookie_path
    expect(cookies[:si_uid]).to be_blank
    host! "localhost"
    get stape_cookie_path, headers: { "Sec-Fetch-Site" => "cross-site" }
    expect(response).to have_http_status(:forbidden)
    expect(cookies[:si_uid]).to be_blank
  end

  it "não emite identificador em HTTP e substitui valores inválidos em HTTPS" do
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"
    https! false
    get stape_cookie_path
    expect(cookies[:si_uid]).to be_blank
    https!
    cookies[:si_uid] = "x" * 100
    get stape_cookie_path
    expect(cookies[:si_uid]).to match(/\A[0-9a-f-]{36}\z/)
  end

  it "preserva identificador válido e remove o cookie quando a integração é desativada" do
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"
    cookies[:si_uid] = "existing_stape-id"
    get stape_cookie_path
    expect(cookies[:si_uid]).to eq("existing_stape-id")

    setting = TrackingIntegrationSetting.current(tenant: Tenant.default)
    setting.stape_enabled = false
    setting.google_tag_manager_enabled = false
    expect(setting.save).to be(true)
    get stape_cookie_path
    expect(cookies[:si_uid]).to be_blank
  end
end
