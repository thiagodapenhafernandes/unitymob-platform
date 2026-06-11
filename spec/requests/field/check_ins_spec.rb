require 'rails_helper'

RSpec.describe "Field::CheckIns", type: :request do
  let(:agent) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }

  before do
    Setting.set("field_checkin_enabled", "true")
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    host! "localhost"
    sign_in agent
  end

  describe "POST /field/check_ins" do
    context "sem turno ativo" do
      it "responde 422 com erro :no_active_shift" do
        post "/field/check_ins", params: {
          lat: store.latitude, lng: store.longitude, accuracy: 10
        }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("no_active_shift")
      end
    end

    context "com turno ativo e GPS dentro do raio" do
      let(:today_wday) { Time.current.in_time_zone("America/Sao_Paulo").wday }

      before do
        create(:store_shift,
               admin_user: agent, store: store,
               day_of_week: today_wday,
               start_time: 1.hour.ago.strftime("%H:%M"),
               end_time: 2.hours.from_now.strftime("%H:%M"))
      end

      it "cria check-in ativo" do
        expect {
          post "/field/check_ins", params: {
            lat: store.latitude, lng: store.longitude, accuracy: 10,
            fingerprint_hash: "ABCDEF123"
          }, as: :json
        }.to change { agent.check_ins.count }.by(1)

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["ok"]).to be true
        expect(body["store_name"]).to eq(store.name)

        ci = agent.reload.active_check_in
        expect(ci).to be_present
        expect(ci.fingerprint_hash).to eq("ABCDEF123")
      end
    end

    context "feature flag desligada" do
      before { Setting.set("field_checkin_enabled", "false") }

      it "retorna 404" do
        post "/field/check_ins", params: { lat: 1, lng: 1 }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /field/check_ins/:id/check_out" do
    let!(:active) { create(:check_in, admin_user: agent, store: store, status: :active) }

    it "fecha o check-in e grava audit log" do
      expect {
        patch "/field/check_ins/#{active.id}/check_out",
              params: { lat: store.latitude, lng: store.longitude },
              as: :json
      }.to change { CheckinAuditLog.where(action: "closed").count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(active.reload.status).to eq("closed_manual")
    end
  end

  private

  def sign_in(admin_user)
    post "/admin/sign_in", params: { admin_user: { email: admin_user.email, password: "password123" } }
  end
end
