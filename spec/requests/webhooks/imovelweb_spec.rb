require "rails_helper"

RSpec.describe "Imovelweb gateway delivery", type: :request do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:connection) { ImovelwebConnection.create!(tenant: tenant, client_code: "unitymob-client", enabled: true, authorized_at: Time.current) }
  let(:entry) { { "event_id" => "evt-1", "event_type" => "CONTACTO", "client_code" => connection.client_code, "environment" => "sandbox", "email" => "contact@example.com", "reference" => "AP-1" } }
  let(:secret) { "s" * 32 }
  before do
    host! "localhost"
    allow(Imovelweb::GatewayClient).to receive(:forwarding_secret).and_return(secret)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("IMOVELWEB_RECEIVING_ENABLED").and_return("true")
  end

  def deliver(route_key = connection.route_key, signing_key = connection.route_key, signature_secret = secret)
    body = entry.to_json
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', signature_secret, "#{signing_key}\n#{body}")}"
    post "/webhooks/imovelweb/#{route_key}", params: body, headers: { "CONTENT_TYPE" => "application/json", "X-Unitymob-Gateway-Provider" => "imovelweb", "X-Unitymob-Gateway-Signature" => signature }
  end

  it "persists before enqueue and handles duplicate delivery" do
    expect { deliver }.to have_enqueued_job(ImovelwebLeadProcessingJob)
    expect(response).to have_http_status(:ok)
    expect { deliver }.not_to change(ImovelwebLeadReceipt, :count)
    expect(response).to have_http_status(:ok)
  end

  it "rejects missing authentication, altered signatures and cross-route replay" do
    deliver(connection.route_key, connection.route_key, "wrong")
    expect(response).to have_http_status(:unauthorized)
    other = ImovelwebConnection.create!(tenant: tenant, client_code: "other")
    deliver(other.route_key)
    expect(response).to have_http_status(:unauthorized)
    expect(ImovelwebLeadReceipt.count).to eq(0)
  end

  it "rejects account/environment mismatch and unsupported events" do
    entry["client_code"] = "another-client"
    deliver
    expect(response).to have_http_status(:conflict)
    entry["client_code"] = connection.client_code
    entry["environment"] = "production"
    deliver
    expect(response).to have_http_status(:conflict)
    entry["event_type"] = "CREDITO"
    deliver
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "fails closed when global switch or client authorization is absent" do
    allow(ENV).to receive(:[]).with("IMOVELWEB_RECEIVING_ENABLED").and_return(nil)
    deliver
    expect(response).to have_http_status(:conflict)
    allow(ENV).to receive(:[]).with("IMOVELWEB_RECEIVING_ENABLED").and_return("true")
    connection.update!(authorized_at: nil)
    deliver
    expect(response).to have_http_status(:conflict)
  end

  it "retains the durable pending receipt and requests redelivery when enqueue fails" do
    allow(ImovelwebLeadProcessingJob).to receive(:perform_later).and_return(false)
    deliver
    expect(response).to have_http_status(:service_unavailable)
    expect(connection.imovelweb_lead_receipts.last.status).to eq("pending")
    allow(ImovelwebLeadProcessingJob).to receive(:perform_later).and_call_original
    expect { deliver }.to have_enqueued_job(ImovelwebLeadProcessingJob)
    expect(response).to have_http_status(:ok)
    expect(connection.imovelweb_lead_receipts.count).to eq(1)
  end

  it "filters individual SQL bind values without request parameters" do
    filter = ActiveRecord::Base.inspection_filter

    expect(filter.filter_param("name", "Example")).to eq("Example")
    expect(filter.filter_param("token", "example-token")).to eq("[FILTERED]")
  end

  it "filters callback PII in request logging" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter(entry.merge("name" => "Secret Name", "phone" => "11999999999", "message" => "private"))).to include("email" => "[FILTERED]", "message" => "[FILTERED]", "name" => "[FILTERED]", "phone" => "[FILTERED]")
  end
end
