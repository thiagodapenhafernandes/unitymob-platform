require "rails_helper"

RSpec.describe Facebook::WhatsappEmbeddedSignupService do
  around do |example|
    old_app_id = ENV["FACEBOOK_APP_ID"]
    old_secret = ENV["FACEBOOK_APP_SECRET"]
    ENV["FACEBOOK_APP_ID"] = "app-id"
    ENV["FACEBOOK_APP_SECRET"] = "app-secret"
    example.run
  ensure
    ENV["FACEBOOK_APP_ID"] = old_app_id
    ENV["FACEBOOK_APP_SECRET"] = old_secret
  end

  it "troca o code por token usando a Graph API" do
    response = instance_double(Net::HTTPSuccess, body: { access_token: "business-token", expires_in: 3600 }.to_json)
    http = instance_double(Net::HTTP)

    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    expect(Net::HTTP).to receive(:start).and_yield(http)
    expect(http).to receive(:get) do |request_uri|
      expect(request_uri).to include("client_id=app-id")
      expect(request_uri).to include("client_secret=app-secret")
      expect(request_uri).to include("code=code-123")
      response
    end

    result = described_class.new(code: "code-123").exchange_code!

    expect(result["access_token"]).to eq("business-token")
  end

  it "retorna erro amigavel quando a Meta nao devolve token" do
    response = instance_double(Net::HTTPBadRequest, body: { error: { message: "Code invalido" } }.to_json)
    http = instance_double(Net::HTTP)

    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:get).and_return(response)

    expect {
      described_class.new(code: "bad-code").exchange_code!
    }.to raise_error(described_class::Error, "Code invalido")
  end

  it "retorna erro amigavel quando a resposta da Meta nao e JSON" do
    response = instance_double(Net::HTTPSuccess, body: "not-json")
    http = instance_double(Net::HTTP)

    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:get).and_return(response)

    expect {
      described_class.new(code: "bad-code").exchange_code!
    }.to raise_error(described_class::Error, "Resposta inválida da Meta ao trocar o código.")
  end
end
