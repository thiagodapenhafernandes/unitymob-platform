require 'rails_helper'

RSpec.describe "Field::LocationPings", type: :request do
  let(:agent) { create(:admin_user, :field_agent) }
  let(:store) { create(:store, out_of_radius_tolerance_minutes: 2) }
  let!(:active_ci) { create(:check_in, admin_user: agent, store: store, status: :active) }

  before do
    Setting.set("field_checkin_enabled", "true")
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    host! "localhost"
    sign_in agent
  end

  describe "POST /field/location_pings" do
    it "cria ping dentro do raio" do
      expect {
        post "/field/location_pings", params: {
          lat: store.latitude, lng: store.longitude, accuracy: 10
        }, as: :json
      }.to change { LocationPing.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be true
      expect(body["inside_radius"]).to be true
    end

    it "sem check-in ativo: 404" do
      active_ci.update!(status: :closed_manual, checked_out_at: Time.current)
      post "/field/location_pings", params: { lat: 1, lng: 1 }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  private

  def sign_in(admin_user)
    post "/admin/sign_in", params: { admin_user: { email: admin_user.email, password: "password123" } }
  end
end
