require 'rails_helper'

RSpec.describe StoreShift, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:store) }
    it { is_expected.to belong_to(:admin_user) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }

    it "aceita day_of_week entre 0-6" do
      (0..6).each do |d|
        expect(build(:store_shift, day_of_week: d)).to be_valid
      end
    end

    it "rejeita day_of_week fora do range" do
      expect(build(:store_shift, day_of_week: 7)).not_to be_valid
      expect(build(:store_shift, day_of_week: -1)).not_to be_valid
    end

    it "rejeita end_time <= start_time" do
      shift = build(:store_shift, start_time: "18:00", end_time: "09:00")
      expect(shift).not_to be_valid
      expect(shift.errors[:end_time]).to be_present
    end
  end

  describe "#day_name" do
    it "retorna nome do dia em pt-BR" do
      expect(build(:store_shift, day_of_week: 1).day_name).to eq("Segunda-feira")
      expect(build(:store_shift, day_of_week: 0).day_name).to eq("Domingo")
    end
  end

  describe "#label" do
    it "formata dia + horário" do
      shift = build(:store_shift, day_of_week: 1, start_time: "09:00", end_time: "18:00")
      expect(shift.label).to eq("Segunda-feira • 09:00–18:00")
    end
  end

  describe "#active_at?" do
    let(:store) { create(:store, timezone: "America/Sao_Paulo") }
    let(:shift) { create(:store_shift, store: store, day_of_week: 1, start_time: "09:00", end_time: "18:00") }

    it "true dentro do horário no dia certo" do
      Time.use_zone("America/Sao_Paulo") do
        monday_noon = Time.zone.local(2026, 4, 20, 12, 0) # segunda
        expect(shift.active_at?(monday_noon)).to be true
      end
    end

    it "false fora do horário mesmo no dia certo" do
      Time.use_zone("America/Sao_Paulo") do
        monday_night = Time.zone.local(2026, 4, 20, 21, 0)
        expect(shift.active_at?(monday_night)).to be false
      end
    end

    it "false em outro dia da semana" do
      Time.use_zone("America/Sao_Paulo") do
        tuesday = Time.zone.local(2026, 4, 21, 12, 0)
        expect(shift.active_at?(tuesday)).to be false
      end
    end

    it "false se shift inativo" do
      shift.update!(active: false)
      Time.use_zone("America/Sao_Paulo") do
        monday_noon = Time.zone.local(2026, 4, 20, 12, 0)
        expect(shift.active_at?(monday_noon)).to be false
      end
    end
  end
end
