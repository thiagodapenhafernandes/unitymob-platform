require "rails_helper"

RSpec.describe "API mobile sessions verify (login guiado)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { host! "localhost" }

  let(:tenant) { Tenant.default }
  let(:admin_user) { create(:admin_user, :field_agent, tenant: tenant, email: "guiado-#{SecureRandom.hex(4)}@salute.test") }

  before { tenant.update!(require_two_factor: true) }

  def login_step_up
    post "/api/v1/field/sessions", params: { email: admin_user.email, password: "password123" }, as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  def totp_now(secret)
    ROTP::TOTP.new(secret).now
  end

  context "enrollment" do
    it "completa a matrícula e emite o JWT pleno com backup codes" do
      body = login_step_up
      expect(body["status"]).to eq("enrollment_required")

      post "/api/v1/field/sessions/verify",
           params: { token: body["enrollment_token"], code: totp_now(body["manual_key"]) }, as: :json

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result["status"]).to eq("ok")
      expect(result["token"]).to be_present
      expect(result["backup_codes"].size).to be >= 1
      expect(admin_user.reload.otp_enabled?).to be(true)

      get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{result["token"]}" }
      expect(response).to have_http_status(:ok)
    end

    it "rejeita código errado sem matricular" do
      body = login_step_up

      post "/api/v1/field/sessions/verify",
           params: { token: body["enrollment_token"], code: "000000" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_code")
      expect(admin_user.reload.otp_enabled?).to be(false)
    end

    it "rejeita reuso do token após a matrícula" do
      body = login_step_up
      post "/api/v1/field/sessions/verify",
           params: { token: body["enrollment_token"], code: totp_now(body["manual_key"]) }, as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/field/sessions/verify",
           params: { token: body["enrollment_token"], code: totp_now(body["manual_key"]) }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_token")
    end

    it "responde already_enrolled quando a conta foi ativada entre decode e lock" do
      secret = ROTP::Base32.random
      result = Api::V1::Field::MfaStepUp::Result.new(user: admin_user, purpose: "field_mfa_enrollment",
        payload: { "setup_secret" => secret })
      allow(Api::V1::Field::MfaStepUp).to receive(:decode).and_return(result)
      admin_user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)

      post "/api/v1/field/sessions/verify",
           params: { token: "stale", code: totp_now(secret) }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("already_enrolled")
    end
  end

  context "challenge" do
    before { admin_user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current) }

    it "emite o JWT pleno com TOTP válido" do
      body = login_step_up
      expect(body["status"]).to eq("challenge_required")

      post "/api/v1/field/sessions/verify",
           params: { token: body["challenge_token"], code: totp_now(admin_user.otp_secret) }, as: :json

      expect(response).to have_http_status(:ok)
      token = JSON.parse(response.body)["token"]
      expect(token).to be_present

      get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
    end

    it "aceita backup code de uso único" do
      codes = admin_user.generate_backup_codes!
      body = login_step_up

      post "/api/v1/field/sessions/verify",
           params: { token: body["challenge_token"], code: codes.first }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["token"]).to be_present
      expect(admin_user.reload.otp_backup_codes.size).to eq(codes.size - 1)
    end

    it "rejeita reuso do token após o sucesso (timestep consumido)" do
      body = login_step_up
      post "/api/v1/field/sessions/verify",
           params: { token: body["challenge_token"], code: totp_now(admin_user.otp_secret) }, as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/field/sessions/verify",
           params: { token: body["challenge_token"], code: totp_now(admin_user.otp_secret) }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_token")
    end

    it "bloqueia após 5 códigos errados" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      body = login_step_up

      5.times do
        post "/api/v1/field/sessions/verify",
             params: { token: body["challenge_token"], code: "000000" }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
      post "/api/v1/field/sessions/verify",
           params: { token: body["challenge_token"], code: totp_now(admin_user.otp_secret) }, as: :json

      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)["error"]).to eq("too_many_attempts")
    end
  end

  context "invariantes do token de step-up" do
    it "não autoriza endpoints operacionais (nem challenge nem enrollment)" do
      admin_user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
      challenge = login_step_up["challenge_token"]
      admin_user.update!(otp_secret: nil, otp_enabled_at: nil)
      enrollment = login_step_up["enrollment_token"]

      get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{challenge}" }
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{enrollment}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejeita token adulterado, expirado e JWT pleno no lugar do step-up" do
      body = login_step_up
      tampered = body["enrollment_token"][0..-3] + "xx"

      post "/api/v1/field/sessions/verify", params: { token: tampered, code: "000000" }, as: :json
      expect(JSON.parse(response.body)["error"]).to eq("invalid_token")

      tenant.update!(require_two_factor: false)
      post "/api/v1/field/sessions", params: { email: admin_user.email, password: "password123" }, as: :json
      full = JSON.parse(response.body)["token"]

      post "/api/v1/field/sessions/verify", params: { token: full, code: "000000" }, as: :json
      expect(JSON.parse(response.body)["error"]).to eq("invalid_token")
    end

    it "rejeita token expirado" do
      body = login_step_up
      travel_to 6.minutes.from_now do
        post "/api/v1/field/sessions/verify",
             params: { token: body["enrollment_token"], code: "000000" }, as: :json
      end

      expect(JSON.parse(response.body)["error"]).to eq("invalid_token")
    end

    it "rejeita usuário desativado entre emissão e verificação" do
      body = login_step_up
      admin_user.update!(active: false)

      post "/api/v1/field/sessions/verify",
           params: { token: body["enrollment_token"], code: "000000" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "throttle do verify" do
    before do
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.enabled = true
      Rack::Attack.reset!
    end

    after { Rack::Attack.reset! }

    it "retorna 429 após rajada no verify" do
      13.times do
        post "/api/v1/field/sessions/verify", params: { token: "x", code: "000000" }, as: :json
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
