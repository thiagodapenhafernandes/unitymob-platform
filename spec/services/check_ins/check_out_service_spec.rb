require 'rails_helper'

RSpec.describe CheckIns::CheckOutService do
  let(:user) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }

  describe "#call" do
    context "com check-in ativo" do
      let(:check_in) { create(:check_in, admin_user: user, store: store, status: :active) }

      it "fecha com sucesso status closed_manual por default" do
        result = described_class.new(check_in: check_in).call
        expect(result[:success]).to be true
        expect(check_in.reload.closed_manual?).to be true
        expect(check_in.checked_out_at).to be_present
      end

      it "aceita razão customizada" do
        result = described_class.new(check_in: check_in, reason: :closed_auto_out_of_radius).call
        expect(result[:success]).to be true
        expect(check_in.reload.closed_auto_out_of_radius?).to be true
      end

      it "grava coordenadas de checkout quando informadas" do
        described_class.new(check_in: check_in, lat: -26.99, lng: -48.63, accuracy: 5).call
        reloaded = check_in.reload
        expect(reloaded.checkout_latitude).to be_within(0.01).of(-26.99)
        expect(reloaded.checkout_accuracy_meters).to eq(5)
      end

      it "retorna as coordenadas de checkout no check_in devolvido (sem zerar pós-reload)" do
        result = described_class.new(check_in: check_in, lat: -26.99, lng: -48.63, accuracy: 5).call
        expect(result[:success]).to be true
        expect(result[:check_in].checkout_latitude).to be_within(0.01).of(-26.99)
        expect(result[:check_in].checkout_longitude).to be_within(0.01).of(-48.63)
      end

      it "é idempotente: um segundo check-out no mesmo registro vira no-op :not_active" do
        first = described_class.new(check_in: check_in).call
        expect(first[:success]).to be true

        # Segunda instância operando sobre o mesmo registro (double-tap/retry):
        # sob lock, revalida ativo e não deve refechar nem duplicar auditoria.
        second_ref = CheckIn.find(check_in.id)
        audit_before = CheckinAuditLog.where(check_in_id: check_in.id).count

        second = described_class.new(check_in: second_ref).call
        expect(second[:success]).to be false
        expect(second[:error]).to eq(:not_active)
        expect(CheckinAuditLog.where(check_in_id: check_in.id).count).to eq(audit_before)
      end
    end

    context "com check-in já fechado" do
      let(:check_in) { create(:check_in, admin_user: user, store: store, status: :closed_manual, checked_out_at: 1.hour.ago) }

      it "retorna erro :not_active" do
        result = described_class.new(check_in: check_in).call
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:not_active)
      end
    end

    context "com check_in nil" do
      it "retorna erro :not_active" do
        result = described_class.new(check_in: nil).call
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:not_active)
      end
    end
  end
end
