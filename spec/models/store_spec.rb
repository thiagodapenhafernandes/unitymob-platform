require 'rails_helper'

RSpec.describe Store, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:director).class_name("AdminUser").optional }
    it { is_expected.to belong_to(:footer_store).optional }
    it { is_expected.to have_many(:store_shifts).dependent(:destroy) }
    it { is_expected.to have_many(:agents).through(:store_shifts) }
  end

  describe "validations" do
    subject { build(:store) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_numericality_of(:geofence_radius_meters).is_greater_than(0).is_less_than_or_equal_to(5000) }

    it "rejeita timezone inválido" do
      store = build(:store, timezone: "Invalid/TZ")
      expect(store).not_to be_valid
      expect(store.errors[:timezone]).to include("não é um fuso horário válido")
    end

    it "aceita timezone válido" do
      store = build(:store, timezone: "America/Sao_Paulo")
      expect(store).to be_valid
    end

    it "rejeita latitude fora do range" do
      store = build(:store, latitude: 95.0, longitude: -48.6348)
      expect(store).not_to be_valid
      expect(store.errors[:latitude]).to be_present
    end

    it "rejeita longitude fora do range" do
      store = build(:store, latitude: -26.9906, longitude: 185.0)
      expect(store).not_to be_valid
      expect(store.errors[:longitude]).to be_present
    end

    it "rejeita diretor de outra conta" do
      tenant = Tenant.create!(name: "Conta A", slug: "conta-a-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Conta B", slug: "conta-b-#{SecureRandom.hex(3)}")
      director_profile = Profile.create!(tenant: other_tenant, name: "Operacional", axis: "vertical", position: 50)
      director = create(:admin_user, tenant: other_tenant, profile: director_profile)
      store = build(:store, tenant: tenant, director: director)

      expect(store).not_to be_valid
      expect(store.errors[:director]).to include("deve pertencer à mesma conta da loja")
    end

    it "aceita diretor da mesma conta" do
      tenant = Tenant.create!(name: "Conta C", slug: "conta-c-#{SecureRandom.hex(3)}")
      director_profile = Profile.create!(tenant: tenant, name: "Operacional", axis: "vertical", position: 50)
      director = create(:admin_user, tenant: tenant, profile: director_profile)
      store = build(:store, tenant: tenant, director: director)

      expect(store).to be_valid
    end
  end

  describe "friendly_id slug" do
    it "gera slug a partir do nome" do
      store = create(:store, name: "Loja Centro")
      expect(store.slug).to start_with("loja-centro")
    end

    it "é único" do
      create(:store, name: "Loja Única")
      s2 = create(:store, name: "Loja Única")
      expect(s2.slug).not_to eq("loja-unica")
    end
  end

  describe "coordenadas e PostGIS" do
    it "grava latitude/longitude no campo location (EWKT)" do
      store = create(:store, latitude: -26.9906, longitude: -48.6348)
      reloaded = Store.find(store.id)
      expect(reloaded.latitude).to be_within(0.0001).of(-26.9906)
      expect(reloaded.longitude).to be_within(0.0001).of(-48.6348)
    end

    it "retorna nil coords quando não informadas" do
      store = build(:store, :without_location)
      store.save(validate: false)
      reloaded = Store.find(store.id)
      expect(reloaded.latitude).to be_nil
      expect(reloaded.longitude).to be_nil
    end
  end

  describe ".within_geofence_of" do
    let!(:centro) { create(:store, name: "Centro", latitude: -26.9906, longitude: -48.6348, geofence_radius_meters: 150) }
    let!(:atlantica) { create(:store, name: "Atlântica", latitude: -26.9886, longitude: -48.6308, geofence_radius_meters: 150) }
    let!(:sao_paulo) { create(:store, name: "SP", latitude: -23.55, longitude: -46.63, geofence_radius_meters: 150) }

    it "retorna só lojas dentro do próprio raio de um ponto" do
      result = Store.within_geofence_of(-26.9906, -48.6348)
      expect(result.pluck(:name)).to contain_exactly("Centro")
    end

    it "retorna vazio quando ponto longe de qualquer loja" do
      expect(Store.within_geofence_of(0, 0)).to be_empty
    end

    it "retorna vazio com coordenadas em branco" do
      expect(Store.within_geofence_of(nil, nil)).to be_empty
    end

    it "ignora lojas inativas" do
      centro.update!(active: false)
      expect(Store.within_geofence_of(-26.9906, -48.6348)).to be_empty
    end
  end

  describe ".by_distance_from" do
    let!(:a) { create(:store, name: "A", latitude: -26.9906, longitude: -48.6348) }
    let!(:b) { create(:store, name: "B", latitude: -26.9886, longitude: -48.6308) }

    it "ordena lojas por distância ascendente" do
      result = Store.by_distance_from(-26.9906, -48.6348)
      expect(result.map(&:name)).to eq(["A", "B"])
      expect(result.first["distance_meters"].to_f).to be < result.last["distance_meters"].to_f
    end
  end

  describe "#contains?" do
    let(:store) { create(:store, latitude: -26.9906, longitude: -48.6348, geofence_radius_meters: 150) }

    it "true dentro do raio" do
      expect(store.contains?(-26.9906, -48.6348)).to be true
    end

    it "false fora do raio" do
      # ~450m de distância
      expect(store.contains?(-26.9906, -48.6398)).to be false
    end
  end

  describe "#distance_meters_to" do
    let(:store) { create(:store, latitude: -26.9906, longitude: -48.6348) }

    it "calcula distância em metros" do
      expect(store.distance_meters_to(-26.9906, -48.6348)).to be < 1.0
      expect(store.distance_meters_to(-26.9906, -48.6398)).to be_between(400, 600)
    end

    it "retorna nil se sem coords na loja" do
      s = build(:store, :without_location)
      s.save(validate: false)
      expect(s.distance_meters_to(-26.9906, -48.6348)).to be_nil
    end
  end
end
