require 'rails_helper'

RSpec.describe FieldFeatureGate, type: :controller do
  before do
    Current.reset
    Setting.where(key: FieldFeatureGate::SETTING_KEY).delete_all
  end

  after { Current.reset }

  # Controller anônimo pra testar o concern isoladamente
  controller(ActionController::Base) do
    include FieldFeatureGate
    before_action :ensure_field_enabled!

    def index
      render plain: "ok"
    end
  end

  describe "#ensure_field_enabled!" do
    context "quando flag desligada" do
      before { Setting.set("field_checkin_enabled", "false") }

      it "retorna 404 em html" do
        get :index
        expect(response).to have_http_status(:not_found)
      end

      it "retorna 404 JSON quando request for JSON" do
        get :index, format: :json
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)).to include("error" => "feature_disabled")
      end
    end

    context "quando flag ligada" do
      before { Setting.set("field_checkin_enabled", "true") }

      it "passa e renderiza action" do
        get :index
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("ok")
      end
    end
  end

  describe ".field_checkin_enabled?" do
    it "true quando Setting está true" do
      Setting.set("field_checkin_enabled", "true")
      expect(FieldFeatureGate.field_checkin_enabled?).to be true
    end

    it "false por default" do
      Setting.where(key: "field_checkin_enabled").destroy_all
      expect(FieldFeatureGate.field_checkin_enabled?).to be false
    end
  end
end
