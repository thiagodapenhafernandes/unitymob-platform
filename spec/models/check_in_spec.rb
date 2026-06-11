require 'rails_helper'

RSpec.describe CheckIn, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:admin_user) }
    it { is_expected.to belong_to(:store) }
    it { is_expected.to belong_to(:store_shift).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:checked_in_at) }
  end

  describe "enum status" do
    it "tem os 5 estados esperados" do
      expect(CheckIn.statuses).to include(
        "active", "closed_manual", "closed_auto_shift_end",
        "closed_auto_out_of_radius", "closed_admin_force"
      )
    end
  end

  describe "unique active check-in per user" do
    let(:user) { create(:admin_user, :field_agent) }
    let(:store) { create(:store) }

    it "permite múltiplos check-ins fechados pro mesmo user" do
      create(:check_in, admin_user: user, store: store, status: :closed_manual, checked_out_at: Time.current)
      expect { create(:check_in, admin_user: user, store: store, status: :closed_manual, checked_out_at: Time.current) }
        .not_to raise_error
    end

    it "impede 2 check-ins ativos simultâneos pro mesmo user" do
      create(:check_in, admin_user: user, store: store, status: :active)
      expect { create(:check_in, admin_user: user, store: store, status: :active) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "permite um usuário com ativo + fechado anterior" do
      create(:check_in, admin_user: user, store: store, status: :closed_manual, checked_out_at: 1.hour.ago)
      expect { create(:check_in, admin_user: user, store: store, status: :active) }.not_to raise_error
    end
  end

  describe "coordenadas PostGIS" do
    it "grava checkin_latitude/longitude como POINT" do
      check_in = create(:check_in, checkin_latitude: -26.9906, checkin_longitude: -48.6348)
      reloaded = CheckIn.find(check_in.id)
      expect(reloaded.checkin_latitude).to be_within(0.0001).of(-26.9906)
      expect(reloaded.checkin_longitude).to be_within(0.0001).of(-48.6348)
    end
  end

  describe "#duration" do
    it "retorna duração entre checked_in_at e Time.current se ativo" do
      check_in = create(:check_in, checked_in_at: 2.hours.ago)
      expect(check_in.duration).to be_within(10).of(2.hours)
    end

    it "retorna duração entre checked_in_at e checked_out_at se fechado" do
      check_in = create(:check_in, checked_in_at: 3.hours.ago, checked_out_at: 1.hour.ago, status: :closed_manual)
      expect(check_in.duration).to be_within(10).of(2.hours)
    end
  end

  describe "#force_close!" do
    let(:check_in) { create(:check_in) }

    it "marca como fechado com o status informado" do
      check_in.force_close!(reason: :closed_manual, lat: -26.99, lng: -48.63)
      expect(check_in.reload.closed_manual?).to be true
      expect(check_in.checked_out_at).to be_present
      expect(check_in.checkout_latitude).to be_within(0.01).of(-26.99)
    end
  end

  describe "AdminUser#active_check_in" do
    let(:user) { create(:admin_user, :field_agent) }

    it "retorna o check-in ativo do usuário" do
      check_in = create(:check_in, admin_user: user, status: :active)
      expect(user.active_check_in).to eq(check_in)
    end

    it "retorna nil se todos os check-ins estão fechados" do
      create(:check_in, admin_user: user, status: :closed_manual, checked_out_at: 1.hour.ago)
      expect(user.active_check_in).to be_nil
    end
  end
end
