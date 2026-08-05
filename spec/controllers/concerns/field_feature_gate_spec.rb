require 'rails_helper'

RSpec.describe FieldFeatureGate, type: :controller do
  let(:tenant) do
    Tenant.find_or_create_by!(slug: "field-gate-spec") do |record|
      record.name = "Field gate spec"
      record.active = true
    end
  end

  before do
    Current.reset
    Current.tenant = tenant
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

    def current_tenant
      Tenant.find_by(slug: "field-gate-spec")
    end
  end

  describe "#ensure_field_enabled!" do
    context "quando flag desligada" do
      before { Setting.set("field_checkin_enabled", "false", tenant: tenant) }

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
      before { Setting.set("field_checkin_enabled", "true", tenant: tenant) }

      it "passa e renderiza action" do
        get :index
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("ok")
      end
    end
  end

  describe ".field_checkin_enabled?" do
    it "true quando Setting está true" do
      Setting.set("field_checkin_enabled", "true", tenant: tenant)
      expect(FieldFeatureGate.field_checkin_enabled?(tenant: tenant)).to be true
    end

    it "false por default" do
      Setting.where(key: "field_checkin_enabled").destroy_all
      expect(FieldFeatureGate.field_checkin_enabled?(tenant: tenant)).to be false
    end

    it "não herda flag global em tenant sem configuração" do
      Setting.set("field_checkin_enabled", "true", tenant: nil)

      expect(FieldFeatureGate.field_checkin_enabled?(tenant: tenant)).to be false
    end
  end
end
