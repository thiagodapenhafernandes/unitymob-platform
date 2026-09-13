require "rails_helper"
RSpec.describe "Instagram Direct webhook", type: :request do
  let(:payload) { {object: "instagram", entry: [{id: "12345", messaging: [{sender: {id: "98765"}, recipient: {id: "12345"}, message: {mid: "m1", text: "Olá"}}]}]}.to_json }
  before do
    host! "localhost"
    allow_any_instance_of(Webhooks::MetaController).to receive(:meta_webhook_app_secret).and_return("secret")
  end
  it "valida assinatura e agenda o evento" do
    signature = OpenSSL::HMAC.hexdigest("SHA256", "secret", payload)
    expect { post "/webhooks/meta", params: payload, headers: {"CONTENT_TYPE" => "application/json", "X-Hub-Signature-256" => "sha256=#{signature}"} }.to have_enqueued_job(InstagramDirectJob)
    expect(response).to have_http_status(:ok)
  end
  it "recusa assinatura inválida" do
    expect { post "/webhooks/meta", params: payload, headers: {"CONTENT_TYPE" => "application/json", "X-Hub-Signature-256" => "sha256=invalid"} }.not_to have_enqueued_job(InstagramDirectJob)
    expect(response).to have_http_status(:forbidden)
  end
end
