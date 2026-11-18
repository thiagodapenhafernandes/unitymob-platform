require "rails_helper"

RSpec.describe "Chaves na Mão validation capture", type: :request do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:token) { "chaves-test-credential-#{'x' * 32}" }
  let(:connection) { ChavesNaMaoConnection.create!(tenant: tenant, account_code: "33380", integration_token: token, enabled: true) }
  let(:payload) { { "id" => "test-1", "contact" => { "name" => "Teste", "phone" => "11999999999" } }.to_json }

  before { host! "localhost" }

  def deliver(body: payload, authorization: "Bearer #{token}", route_key: connection.route_key)
    post "/webhooks/chaves_na_mao/#{route_key}", params: body,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => authorization }
  end

  it "captures an encrypted receipt without creating, distributing or notifying a lead" do
    connection
    jobs = enqueued_jobs.size
    expect { deliver }.not_to change(Lead, :count)
    expect(response).to have_http_status(:ok)
    receipt = connection.chaves_na_mao_lead_receipts.sole
    expect(receipt.payload).to eq(payload)
    expect(receipt.payload_before_type_cast).not_to include("11999999999")
    expect(connection.integration_token_before_type_cast).not_to include(token)
    expect(enqueued_jobs.size).to eq(jobs)
  end

  it "acknowledges an identical retry without storing another event" do
    deliver
    expect { deliver }.not_to change(ChavesNaMaoLeadReceipt, :count)
    expect(response).to have_http_status(:ok)
  end

  it "supports a Basic header containing the configured token" do
    deliver(authorization: "Basic #{token}")
    expect(response).to have_http_status(:ok)
  end

  it "rejects invalid and missing credentials" do
    ["", "Bearer wrong"].each do |authorization|
      expect { deliver(authorization: authorization) }.not_to change(ChavesNaMaoLeadReceipt, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "isolates receipts by connection and ignores tenant identifiers in the payload" do
    other = Tenant.create!(name: "Outra conta", slug: "chaves-outro-#{SecureRandom.hex(4)}")
    other_connection = ChavesNaMaoConnection.create!(tenant: other, account_code: "444", integration_token: "z" * 64, enabled: true)
    deliver(body: { tenant_id: other.id, account_code: "444" }.to_json)
    expect(response).to have_http_status(:ok)
    expect(other_connection.chaves_na_mao_lead_receipts.count).to eq(0)
    expect(connection.chaves_na_mao_lead_receipts.count).to eq(1)
    deliver(route_key: other_connection.route_key)
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects disabled connections and unknown routes" do
    connection.update!(enabled: false)
    deliver
    expect(response).to have_http_status(:conflict)
    deliver(route_key: SecureRandom.uuid)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects inactive tenants" do
    connection.tenant.update!(active: false)
    deliver
    expect(response).to have_http_status(:conflict)
  end

  it "rejects malformed, oversized and non-object bodies" do
    ["[]", "{}"].each do |body|
      deliver(body: body)
      expect(response).to have_http_status(:unprocessable_entity)
    end
    deliver(body: { value: "x" * 65.kilobytes }.to_json)
    expect(response).to have_http_status(:payload_too_large)
    deliver(body: "{")
    expect(response).to have_http_status(:bad_request)
  end

  it "filters the entire provider envelope from request logs" do
    logged = nil
    subscriber = ->(_name, _start, _finish, _id, event) { logged = event[:params] }
    ActiveSupport::Notifications.subscribed(subscriber, "start_processing.action_controller") { deliver }
    expect(logged).not_to have_key("contact")
    expect(logged.to_json).not_to include("11999999999", "Teste")
  end
end
