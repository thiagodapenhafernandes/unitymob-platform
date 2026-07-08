require 'rails_helper'

RSpec.describe CheckIns::CreateService do
  let(:user) { create(:admin_user) }
  let!(:store) { create(:store, latitude: -26.9906, longitude: -48.6348, geofence_radius_meters: 150) }

  before do
    Setting.set("field_checkin_enabled", "true")
    now = Time.current.in_time_zone(store.timezone_obj)
    store.update!(turnos_config: operational_shift_config_for(now))
  end

  describe "#call" do
    context "fluxo feliz" do
      subject(:result) { described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10).call }

      it "cria um CheckIn ativo" do
        expect(result[:success]).to be true
        expect(result[:check_in]).to be_persisted
        expect(result[:check_in].active?).to be true
      end

      it "vincula o turno operacional da loja" do
        expect(result[:check_in].store_shift).to be_nil
        expect(result[:check_in].turno).to eq("manha")
        expect(result[:check_in].status_chegada).to eq("sorteio")
      end

      it "retorna distância em metros" do
        expect(result[:distance_meters]).to be_within(5).of(0)
      end
    end

    context "feature flag desligada" do
      before { Setting.set("field_checkin_enabled", "false") }

      it "falha com :feature_disabled" do
        result = described_class.new(admin_user: user, lat: -26.99, lng: -48.63).call
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:feature_disabled)
      end
    end

    context "usuário bloqueado pontualmente" do
      it "falha com :not_field_agent" do
        u = create(:admin_user)
        FieldFeatureGate.disable_agent!(u, tenant: u.tenant)

        result = described_class.new(admin_user: u, lat: -26.99, lng: -48.63).call

        expect(result[:error]).to eq(:not_field_agent)
      end
    end

    context "já tem check-in ativo" do
      it "falha com :already_active" do
        create(:check_in, admin_user: user, store: store, status: :active)
        result = described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10).call
        expect(result[:error]).to eq(:already_active)
      end
    end

    context "accuracy ruim" do
      it "falha com :invalid_accuracy quando accuracy > 50m" do
        result = described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 100).call
        expect(result[:error]).to eq(:invalid_accuracy)
      end
    end

    context "fora do raio" do
      it "falha com :no_store_in_range" do
        result = described_class.new(admin_user: user, lat: -23.5, lng: -46.6, accuracy: 10).call
        expect(result[:error]).to eq(:no_store_in_range)
      end
    end

    context "multi-tenant" do
      it "não cria check-in em loja de outro tenant dentro do raio" do
        other_tenant = Tenant.create!(name: "Outro create check-in #{SecureRandom.hex(3)}", slug: "outro-create-checkin-#{SecureRandom.hex(3)}")
        create(:store, tenant: other_tenant, latitude: -26.9906, longitude: -48.6348, geofence_radius_meters: 150)
        store.update!(latitude: -26.9800, longitude: -48.6200, geofence_radius_meters: 50)

        result = described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq(:no_store_in_range)
      end
    end

    context "sem turno ativo" do
      it "falha com :no_active_shift" do
        store.update!(turnos_config: operational_shift_config_for(Time.current.in_time_zone(store.timezone_obj), active: false))
        result = described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10).call
        expect(result[:error]).to eq(:no_active_shift)
      end
    end

    context "coordenadas ausentes" do
      it "falha com :missing_coordinates" do
        result = described_class.new(admin_user: user, lat: nil, lng: nil).call
        expect(result[:error]).to eq(:missing_coordinates)
      end
    end

    context "coordenadas fora de faixa / trocadas" do
      it "falha com :invalid_coordinates quando lat fora de -90..90" do
        result = described_class.new(admin_user: user, lat: 200, lng: -48.6348, accuracy: 10).call
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:invalid_coordinates)
      end

      it "falha com :invalid_coordinates quando lat/lng estão trocados (lng fora de faixa)" do
        # lat=-48.63 (válido em faixa) mas lng=-260 fora de faixa
        result = described_class.new(admin_user: user, lat: -48.6348, lng: -260, accuracy: 10).call
        expect(result[:error]).to eq(:invalid_coordinates)
      end

      it "falha com :invalid_coordinates para valores não numéricos" do
        result = described_class.new(admin_user: user, lat: "abc", lng: "-48.6", accuracy: 10).call
        expect(result[:error]).to eq(:invalid_coordinates)
      end
    end

    context "accuracy obrigatória para check-in por GPS" do
      it "falha com :invalid_accuracy quando accuracy é OMITIDA" do
        result = described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348).call
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:invalid_accuracy)
      end

      it "falha com :invalid_accuracy quando accuracy <= 0" do
        result = described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 0).call
        expect(result[:error]).to eq(:invalid_accuracy)
      end

      it "aceita check-in MANUAL sem accuracy (exceção legítima)" do
        result = described_class.new(
          admin_user: user, lat: -26.9906, lng: -48.6348,
          device_info: { "manual" => true }
        ).call
        expect(result[:success]).to be true
      end
    end

    context "antifraude no create — mock location" do
      it "marca o check-in como suspeito quando o device reporta mock location" do
        result = described_class.new(
          admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10,
          device_info: { "is_mock_location" => true }
        ).call

        expect(result[:success]).to be true
        check_in = result[:check_in]
        expect(check_in.suspicious).to be true
        expect(Array(check_in.suspicious_reasons)).to include("mock_location")
      end

      it "persiste o sinal is_mock_location no device_info do check-in" do
        result = described_class.new(
          admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10,
          device_info: { "is_mock_location" => "true" }
        ).call

        expect(result[:check_in].device_info["is_mock_location"]).to be true
      end

      it "não marca suspeito quando não há mock location" do
        result = described_class.new(
          admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10,
          device_info: { "is_mock_location" => false }
        ).call

        expect(result[:success]).to be true
        expect(result[:check_in].suspicious).to be false
      end

      it "audita flagged_suspicious quando mock location" do
        expect {
          described_class.new(
            admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10,
            device_info: { "is_mock_location" => true }
          ).call
        }.to change { CheckinAuditLog.where(action: "flagged_suspicious").count }.by(1)
      end
    end
  end

  def operational_shift_config_for(time, active: true)
    entry_start = (time - 30.minutes).strftime("%H:%M")
    entry_end = (time + 30.minutes).strftime("%H:%M")
    pos_end = (time + 60.minutes).strftime("%H:%M")
    out_end = (time + 90.minutes).strftime("%H:%M")

    Store.default_turnos_config.deep_merge(
      "manha" => {
        "ativo" => active,
        "entrada" => { "inicio" => entry_start, "fim" => entry_end },
        "pos_risca" => { "inicio" => entry_end, "fim" => pos_end },
        "fora_roleta" => { "inicio" => pos_end, "fim" => out_end }
      },
      "tarde" => { "ativo" => false },
      "unico" => { "ativo" => false }
    )
  end
end
