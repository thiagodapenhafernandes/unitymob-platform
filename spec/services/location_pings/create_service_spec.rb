require 'rails_helper'

RSpec.describe LocationPings::CreateService do
  let(:user) { create(:admin_user, :field_agent) }
  let(:store) { create(:store, latitude: -26.9906, longitude: -48.6348, geofence_radius_meters: 150, out_of_radius_tolerance_minutes: 2) }
  let(:check_in) { create(:check_in, admin_user: user, store: store, status: :active) }

  describe "#call" do
    context "ping dentro do raio" do
      it "cria ping com inside_radius=true" do
        result = described_class.new(check_in: check_in, lat: -26.9906, lng: -48.6348, accuracy: 5).call
        expect(result[:success]).to be true
        expect(result[:ping].inside_radius).to be true
        expect(result[:inside_radius]).to be true
        expect(result[:auto_checked_out]).to be false
      end

      it "limpa out_of_radius_since quando volta pro raio" do
        check_in.update_column(:out_of_radius_since, 5.minutes.ago)
        described_class.new(check_in: check_in, lat: -26.9906, lng: -48.6348, accuracy: 5).call
        expect(check_in.reload.out_of_radius_since).to be_nil
      end
    end

    context "ping fora do raio — primeiro evento" do
      it "cria ping inside_radius=false e marca out_of_radius_since no check_in" do
        result = described_class.new(check_in: check_in, lat: -26.9906, lng: -48.6400, accuracy: 5).call
        expect(result[:success]).to be true
        expect(result[:ping].inside_radius).to be false
        expect(check_in.reload.out_of_radius_since).to be_within(10.seconds).of(Time.current)
        expect(result[:auto_checked_out]).to be false
      end
    end

    context "ping fora do raio — passou da tolerância" do
      before do
        check_in.update_column(:out_of_radius_since, 5.minutes.ago) # tolerance=2min
      end

      it "dispara auto-checkout com status closed_auto_out_of_radius" do
        result = described_class.new(check_in: check_in, lat: -26.9906, lng: -48.6400, accuracy: 5).call
        expect(result[:success]).to be true
        expect(result[:auto_checked_out]).to be true
        expect(check_in.reload.closed_auto_out_of_radius?).to be true
      end
    end

    context "sem check-in ativo" do
      it "falha com :no_active_check_in" do
        check_in.update!(status: :closed_manual, checked_out_at: Time.current)
        result = described_class.new(check_in: check_in, lat: -26.99, lng: -48.63).call
        expect(result[:error]).to eq(:no_active_check_in)
      end
    end

    context "sem coordenadas" do
      it "falha com :missing_coordinates" do
        result = described_class.new(check_in: check_in, lat: nil, lng: nil).call
        expect(result[:error]).to eq(:missing_coordinates)
      end
    end

    context "coordenadas fora da faixa geográfica" do
      it "rejeita lat/lng implausíveis com :invalid_coordinates (antes do PostGIS)" do
        result = described_class.new(check_in: check_in, lat: 999, lng: -48.63).call
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:invalid_coordinates)
        expect(LocationPing.where(check_in_id: check_in.id)).to be_empty
      end
    end
  end
end
