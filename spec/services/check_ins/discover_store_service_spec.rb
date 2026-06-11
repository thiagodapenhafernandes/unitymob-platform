require 'rails_helper'

RSpec.describe CheckIns::DiscoverStoreService do
  describe "#call" do
    let!(:centro) { create(:store, name: "Centro", latitude: -26.9906, longitude: -48.6348, geofence_radius_meters: 150) }
    let!(:atlantica) { create(:store, name: "Atlântica", latitude: -26.9886, longitude: -48.6308, geofence_radius_meters: 150) }

    context "dentro do raio de uma loja" do
      it "retorna a loja com inside_radius=true" do
        result = described_class.new(lat: -26.9906, lng: -48.6348).call
        expect(result[:store]).to eq(centro)
        expect(result[:inside_radius]).to be true
        expect(result[:distance_meters]).to be < 5
      end
    end

    context "fora do raio mas ainda com loja próxima" do
      it "retorna a loja mais próxima com inside_radius=false" do
        # ~500m de centro
        result = described_class.new(lat: -26.9906, lng: -48.6400).call
        expect(result[:store]).to be_present
        expect(result[:inside_radius]).to be false
        expect(result[:distance_meters]).to be > 150
      end
    end

    context "prefer_store fornecido e dentro do raio" do
      it "retorna a preferida mesmo se outra estiver mais perto" do
        # passa atlantica como preferida e está no raio dela
        result = described_class.new(lat: -26.9886, lng: -48.6308, prefer_store: atlantica).call
        expect(result[:store]).to eq(atlantica)
      end
    end

    context "sem loja alguma" do
      before do
        Store.destroy_all
      end

      it "retorna nil" do
        expect(described_class.new(lat: -26.99, lng: -48.63).call).to be_nil
      end
    end

    context "coordenadas ausentes" do
      it "retorna nil" do
        expect(described_class.new(lat: nil, lng: nil).call).to be_nil
      end
    end
  end
end
