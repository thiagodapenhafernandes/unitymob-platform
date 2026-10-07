require "rails_helper"

RSpec.describe Tiktok::Client do
  let(:client) { described_class.new("access-token") }
  let(:http) { double("HTTP") }
  let(:response) { Net::HTTPOK.new("1.1", "200", "OK") }
  before do
    allow(response).to receive(:body).and_return({ code: 0, data: { access_token: "issued-token", advertiser_ids: ["123"] } }.to_json)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(response)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("TIKTOK_APP_ID").and_return("app-id")
    allow(ENV).to receive(:fetch).with("TIKTOK_APP_SECRET").and_return("app-secret")
  end

  it "exchanges auth_code using Marketing API v1.3 and app credentials" do
    expect(http).to receive(:request) do |request|
      expect(request.path).to eq("/open_api/v1.3/oauth2/access_token/")
      expect(JSON.parse(request.body)).to eq({ "app_id" => "app-id", "secret" => "app-secret", "auth_code" => "code" })
      response
    end
    expect(client.exchange_code("code")["access_token"]).to eq("issued-token")
  end

  it "rejects an API error even when HTTP status is 200 without leaking the response" do
    allow(response).to receive(:body).and_return({ code: 40001, message: "secret data" }.to_json)
    expect { client.accounts }.to raise_error(Tiktok::Client::Error, /permissões/)
  end

  it "paginates published Instant Forms" do
    allow(http).to receive(:request) do |request|
      params = URI.decode_www_form(URI(request.path).query).to_h
      expect(params).to include("advertiser_id" => "123", "business_type" => "LEAD_GEN", "status" => "PUBLISHED")
      page = params.fetch("page")
      allow(response).to receive(:body).and_return({ code: 0, data: { list: [{ page_id: page, title: "Form #{page}" }], page_info: { total_page: 2 } } }.to_json)
      response
    end
    expect(client.forms("123").pluck("page_id")).to eq(["1", "2"])
  end
end
