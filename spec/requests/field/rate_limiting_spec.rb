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

  describe "POST /admin/sign_in limit" do
    it "renderiza orientação em pt-BR para navegação HTML" do
      6.times do
        post "/admin/sign_in",
             params: { admin_user: { email: "pessoa@example.com", password: "invalida" } },
             headers: { "HTTP_ACCEPT" => "text/html" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Muitas tentativas de acesso")
      expect(response.body).to include("20 minutos")
      expect(response.headers["Retry-After"]).to eq("1200")
    end
  end

  describe "GET /imoveis deep page limit" do
    it "retorna 429 após rajada de paginação pública profunda" do
      (Rack::Attack::PUBLIC_PROPERTY_DEEP_PAGE_RATE_LIMIT + 1).times do
        get "/imoveis", params: { page: 51 }, headers: { "REMOTE_ADDR" => "203.0.113.10" }
      end

      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("rate_limited")
    end
  end
end
