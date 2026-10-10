require "rails_helper"

RSpec.describe "API mobile sessions (JWT)", type: :request do
  before { host! "localhost" }

  let(:tenant) { Tenant.default }
  let(:admin_user) { create(:admin_user, :field_agent, tenant: tenant, email: "corretor-#{SecureRandom.hex(4)}@salute.test") }

  it "issues a bearer token for valid credentials and allows access to a protected endpoint" do
    post "/api/v1/field/sessions", params: { email: admin_user.email, password: "password123" }, as: :json

    expect(response).to have_http_status(:ok)
    token = JSON.parse(response.body)["token"]
    expect(token).to be_present

    get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["admin_user"]["email"]).to eq(admin_user.email)
    expect(body["tenant"]["id"]).to eq(tenant.id)
  end

  it "rejects invalid credentials" do
    post "/api/v1/field/sessions", params: { email: admin_user.email, password: "wrong" }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects protected requests without a bearer token" do
    get "/api/v1/field/me"

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects protected requests with a token that has been revoked" do
    post "/api/v1/field/sessions", params: { email: admin_user.email, password: "password123" }, as: :json
    token = JSON.parse(response.body)["token"]

    delete "/api/v1/field/sessions", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:no_content)

    get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "does not authenticate the admin browser session (cookie) via the mobile token endpoints" do
    get "/api/v1/field/me"

    expect(response).to have_http_status(:unauthorized)
  end

  context "when the tenant requires two-factor enrollment" do
    before { tenant.update!(require_two_factor: true) }

    it "returns a guided enrollment (never a full token) for a user who never enrolled in TOTP" do
      post "/api/v1/field/sessions", params: { email: admin_user.email, password: "password123" }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("enrollment_required")
      expect(body["enrollment_token"]).to be_present
      expect(body["provisioning_uri"]).to include("otpauth://")
      expect(body["manual_key"]).to be_present
      expect(body["token"]).to be_nil
    end

    it "returns a challenge (never a full token) for an enrolled user" do
      admin_user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)

      post "/api/v1/field/sessions", params: { email: admin_user.email, password: "password123" }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("challenge_required")
      expect(body["challenge_token"]).to be_present
      expect(body["methods"]).to eq(%w[totp backup_code])
      expect(body["token"]).to be_nil
    end

    it "rejects authenticated calls with a token issued before enrollment was required" do
      tenant.update!(require_two_factor: false)
      post "/api/v1/field/sessions", params: { email: admin_user.email, password: "password123" }, as: :json
      token = JSON.parse(response.body)["token"]
      expect(token).to be_present

      tenant.update!(require_two_factor: true)
      get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("enrollment_required")
    end

    it "lets an enrolled user past the enrollment gate" do
      admin_user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
      token, = Warden::JWTAuth::UserEncoder.new.call(admin_user, :admin_user, nil)

      get "/api/v1/field/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
    end
  end
end
