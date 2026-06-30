require 'rails_helper'

RSpec.describe CheckIns::CreateService do
  let(:user) { create(:admin_user, :field_agent) }
  let!(:store) { create(:store, latitude: -26.9906, longitude: -48.6348, geofence_radius_meters: 150) }

  before do
    Setting.set("field_checkin_enabled", "true")
    user.update!(default_store: store)
    # Cria turno ativo no horário atual
    now = Time.current.in_time_zone(store.timezone_obj)
    start_time = Time.zone.parse("#{now.strftime('%H:%M')}") - 30.minutes
    end_time = Time.zone.parse("#{now.strftime('%H:%M')}") + 30.minutes
    create(:store_shift,
           store: store, admin_user: user, day_of_week: now.wday,
           start_time: start_time, end_time: end_time, active: true)
  end

  describe "#call" do
    context "fluxo feliz" do
      subject(:result) { described_class.new(admin_user: user, lat: -26.9906, lng: -48.6348, accuracy: 10).call }

      it "cria um CheckIn ativo" do
        expect(result[:success]).to be true
        expect(result[:check_in]).to be_persisted
        expect(result[:check_in].active?).to be true
      end

      it "vincula o turno ativo atual" do
        expect(result[:check_in].store_shift).to be_present
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

    context "corretor não é field agent" do
      it "falha com :not_field_agent" do
        u = create(:admin_user) # sem :field_agent
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
        user.store_shifts.destroy_all
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
  end
end
