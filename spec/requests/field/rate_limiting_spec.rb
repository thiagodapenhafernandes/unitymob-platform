require 'rails_helper'

RSpec.describe "Field rate limiting via rack-attack", type: :request do
  before do
    # MemoryStore dedicado para não vazar estado entre specs.
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    host! "localhost"
  end

  after { Rack::Attack.reset! }

  describe "POST /field/location_pings burst limit (2/seg)" do
    it "retorna 429 após 2 requests no mesmo segundo" do
      3.times do
        post "/field/location_pings", params: { latitude: -26.99, longitude: -48.63 }, as: :json
      end
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("rate_limited")
    end
  end

  describe "POST /field/check_ins limit (5/min)" do
    it "retorna 429 após 5 POSTs em um minuto" do
      6.times do
        post "/field/check_ins", params: { latitude: -26.99, longitude: -48.63 }, as: :json
      end
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
