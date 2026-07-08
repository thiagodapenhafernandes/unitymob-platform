require 'rails_helper'

RSpec.describe AntiFraud::CheckIns::Analyzer do
  let(:user) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }
  let(:check_in) { create(:check_in, admin_user: user, store: store, status: :active) }

  def make_ping(lat:, lng:, recorded_at:, accuracy: 10, is_mock_location: false)
    create(:location_ping,
           check_in: check_in,
           admin_user: user,
           latitude: lat,
           longitude: lng,
           recorded_at: recorded_at,
           accuracy_meters: accuracy,
           is_mock_location: is_mock_location)
  end

  describe "#analyze" do
    it "não sinaliza ping normal" do
      ping = make_ping(lat: -26.9906, lng: -48.6348, recorded_at: Time.current)
      result = described_class.analyze_ping(ping)
      expect(result[:suspicious]).to be false
      expect(result[:reasons]).to eq([])
    end

    it "sinaliza mock_location quando is_mock_location=true" do
      ping = make_ping(lat: -26.9906, lng: -48.6348, recorded_at: Time.current, is_mock_location: true)
      result = described_class.analyze_ping(ping)
      expect(result[:suspicious]).to be true
      expect(result[:reasons]).to include("mock_location")
    end

    it "sinaliza velocidade impossível entre dois pings" do
      # Ping 1 em BC, 60s depois em São Paulo (~600km) → ~36000 km/h
      make_ping(lat: -26.9906, lng: -48.6348, recorded_at: 60.seconds.ago)
      ping2 = make_ping(lat: -23.5505, lng: -46.6333, recorded_at: Time.current)

      result = described_class.analyze_ping(ping2)
      expect(result[:suspicious]).to be true
      expect(result[:reasons]).to include("impossible_speed")
    end

    it "NÃO sinaliza alta precisão por si só (aparelho bom não é fraude)" do
      # accuracy baixa mas com jitter real de coordenada — corretor honesto.
      make_ping(lat: -26.99060, lng: -48.63480, recorded_at: 3.minutes.ago, accuracy: 2)
      make_ping(lat: -26.99062, lng: -48.63479, recorded_at: 2.minutes.ago, accuracy: 3)
      ping = make_ping(lat: -26.99059, lng: -48.63481, recorded_at: 1.minute.ago, accuracy: 2)

      result = described_class.analyze_ping(ping)
      expect(result[:reasons]).not_to include("frozen_gps_streak")
      expect(result[:reasons]).not_to include("suspicious_accuracy_streak")
    end

    it "sinaliza GPS congelado: coordenada e accuracy byte-idênticas por vários pings" do
      # Sem jitter algum (variância zero) por FROZEN_GPS_STREAK pings = spoof.
      4.times do |i|
        make_ping(lat: -26.9906, lng: -48.6348, recorded_at: (4 - i).minutes.ago, accuracy: 7)
      end
      ping = make_ping(lat: -26.9906, lng: -48.6348, recorded_at: Time.current, accuracy: 7)

      result = described_class.analyze_ping(ping)
      expect(result[:suspicious]).to be true
      expect(result[:reasons]).to include("frozen_gps_streak")
    end

    it "sinaliza teleporte entre a âncora do check-in e o primeiro ping" do
      # check_in ancorado em BC; primeiro (e único) ping em São Paulo ~600km.
      # Sem par de pings anterior, só a âncora pega o salto.
      check_in.update!(checked_in_at: 60.seconds.ago)
      ping = make_ping(lat: -23.5505, lng: -46.6333, recorded_at: Time.current)

      result = described_class.analyze_ping(ping)
      expect(result[:reasons]).to include("impossible_speed")
    end

    it "sinaliza IP geograficamente distante do ping (>500km)" do
      ping = make_ping(lat: -26.9906, lng: -48.6348, recorded_at: Time.current)
      ping.update!(ip: "8.8.8.8")

      # Mock do resolver — IP mapeado a São Francisco (~10.000km de BC)
      allow(AntiFraud::GeoIpResolver).to receive(:lookup).with("8.8.8.8").and_return(
        latitude: 37.7749, longitude: -122.4194, city: "San Francisco", country: "US"
      )

      result = described_class.analyze_ping(ping.reload)
      expect(result[:reasons]).to include("ip_geo_mismatch")
    end

    it "não sinaliza quando resolver retorna nil (base ausente)" do
      ping = make_ping(lat: -26.9906, lng: -48.6348, recorded_at: Time.current)
      ping.update!(ip: "8.8.8.8")

      allow(AntiFraud::GeoIpResolver).to receive(:lookup).and_return(nil)

      result = described_class.analyze_ping(ping.reload)
      expect(result[:reasons]).not_to include("ip_geo_mismatch")
    end

    it "sinaliza fingerprint duplicado entre admin_users" do
      other_user = create(:admin_user, :field_agent)
      create(:check_in,
             admin_user: other_user,
             store: store,
             status: :active,
             checked_in_at: 1.hour.ago,
             fingerprint_hash: "ABC123")
      check_in.update!(fingerprint_hash: "ABC123")

      ping = make_ping(lat: -26.9906, lng: -48.6348, recorded_at: Time.current)
      ping.reload
      result = described_class.analyze_ping(ping)
      expect(result[:reasons]).to include("duplicate_fingerprint")
    end

    it "não sinaliza fingerprint duplicado de outro tenant" do
      other_tenant = Tenant.create!(name: "Outro antifraude #{SecureRandom.hex(3)}", slug: "outro-antifraude-#{SecureRandom.hex(3)}")
      other_user = create(:admin_user, :field_agent, tenant: other_tenant)
      other_store = create(:store, tenant: other_tenant)
      create(:check_in,
             tenant: other_tenant,
             admin_user: other_user,
             store: other_store,
             status: :active,
             checked_in_at: 1.hour.ago,
             fingerprint_hash: "ABC123")
      check_in.update!(fingerprint_hash: "ABC123")

      ping = make_ping(lat: -26.9906, lng: -48.6348, recorded_at: Time.current)
      result = described_class.analyze_ping(ping.reload)

      expect(result[:reasons]).not_to include("duplicate_fingerprint")
    end
  end
end
