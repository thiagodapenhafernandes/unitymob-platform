require "rails_helper"

RSpec.describe "Chaves na Mão validation capture", type: :request do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:token) { "chaves-test-credential-#{'x' * 32}" }
  let(:connection) { ChavesNaMaoConnection.create!(tenant: tenant, login_email: "cliente@example.com", account_code: "33380", integration_token: token, enabled: true) }
  let(:payload) { { "id" => "test-1", "contact" => { "name" => "Teste", "phone" => "11999999999" } }.to_json }

  before { host! "localhost" }

  def deliver(body: payload, authorization: "Basic #{Base64.strict_encode64("cliente@example.com:#{token}")}", route_key: connection.route_key)
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

  it "supports the documented Basic email and token header" do
    deliver
    expect(response).to have_http_status(:ok)
  end

  it "rejects invalid and missing credentials" do
    ["", "Bearer wrong", "Bearer #{token}", "Basic #{token}", "Basic #{Base64.strict_encode64("wrong@example.com:#{token}")}"].each do |authorization|
      expect { deliver(authorization: authorization) }.not_to change(ChavesNaMaoLeadReceipt, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "isolates receipts by connection and ignores tenant identifiers in the payload" do
    other = Tenant.create!(name: "Outra conta", slug: "chaves-outro-#{SecureRandom.hex(4)}")
    other_connection = ChavesNaMaoConnection.create!(tenant: other, login_email: "outro@example.com", account_code: "444", integration_token: "z" * 64, enabled: true)
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
  it "deduplicates operational events by provider ID even when bytes or delivery time change" do
    connection.update!(operational: true)
    body = { id: "event-1", segment: "REALTY" }
    expect { deliver(body: body.to_json) }.to have_enqueued_job(ChavesNaMaoLeadProcessingJob)
    expect(response).to have_http_status(:ok)
    expect { deliver(body: body.merge(sendAt: "2026-11-26 10:00:01").to_json) }.not_to change(ChavesNaMaoLeadReceipt, :count)
    expect(response).to have_http_status(:ok)
    expect(connection.chaves_na_mao_lead_receipts.sole.status).to eq("pending")
  end

  it "requires a stable string event ID for operational delivery" do
    connection.update!(operational: true)
    [nil, "", 123, "x" * 256].each do |id|
      expect { deliver(body: { id: id }.to_json) }.not_to change(ChavesNaMaoLeadReceipt, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "receives and processes an authenticated official lead end to end" do
    connection.update!(operational: true)
    body = { id: "end-to-end", name: "Cliente", email: "cliente-lead@example.com", phone: "11988776655", segment: "REALTY",
      ad: { id: "98765", title: "Apartamento", purpose: "Venda", reference: nil } }.to_json
    perform_enqueued_jobs(only: ChavesNaMaoLeadProcessingJob) { deliver(body: body) }
    expect(response).to have_http_status(:ok)
    receipt = connection.chaves_na_mao_lead_receipts.sole
    expect(receipt.status).to eq("processed")
    expect(receipt.lead.tenant_id).to eq(tenant.id)
    expect { deliver(body: body) }.not_to have_enqueued_job(ChavesNaMaoLeadProcessingJob)
  end

  it "does not replay captured events on activation but processes a fresh authenticated delivery" do
    deliver
    captured = connection.chaves_na_mao_lead_receipts.sole
    connection.update!(operational: true)
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(ChavesNaMaoLeadProcessingJob)
    expect { deliver }.to change(ChavesNaMaoLeadReceipt, :count).by(1)
    expect(captured.reload.status).to eq("captured")
  end

end
