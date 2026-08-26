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
end
