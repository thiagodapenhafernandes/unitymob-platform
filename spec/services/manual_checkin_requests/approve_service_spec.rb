require 'rails_helper'

RSpec.describe ManualCheckinRequests::ApproveService do
  let(:agent) { create(:admin_user, :field_agent) }
  let(:admin) { create(:admin_user, :admin) }
  let(:store) { create(:store) }
  let(:request) { create(:manual_checkin_request, admin_user: agent, store: store) }

  describe "#call" do
    it "cria check-in com device_info.manual=true e aprova o pedido" do
      result = described_class.new(request: request, reviewer: admin, notes: "Ok, corretor visto na loja").call

      expect(result[:success]).to be true
      ci = result[:check_in]
      expect(ci.status).to eq("active")
      expect(ci.admin_user).to eq(agent)
      expect(ci.store).to eq(store)
      expect(ci.tenant).to eq(request.tenant)
      expect(ci.device_info["manual"]).to be true

      expect(request.reload).to be_approved
      expect(request.approved_check_in).to eq(ci)
      expect(request.review_notes).to eq("Ok, corretor visto na loja")
    end

    it "grava audit log de manual_request_approved" do
      expect {
        described_class.new(request: request, reviewer: admin, notes: "ok").call
      }.to change { CheckinAuditLog.where(action: "manual_request_approved").count }.by(1)
      expect(CheckinAuditLog.where(action: "manual_request_approved").last.tenant).to eq(request.tenant)
    end

    it "falha se já existe check-in ativo" do
      create(:check_in, admin_user: agent, store: store, status: :active)
      result = described_class.new(request: request, reviewer: admin).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq(:already_has_active)
      expect(request.reload).to be_pending
    end

    it "não aprova pedido já resolvido" do
      request.update!(status: :rejected, reviewed_by_admin_user: admin, reviewed_at: Time.current)
      result = described_class.new(request: request, reviewer: admin).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq(:invalid_state)
    end

    it "retorna erro tratado (sem 500) quando o check-in é inválido por loja de outra conta" do
      other_tenant = Tenant.create!(name: "Outro approve #{SecureRandom.hex(3)}", slug: "outro-approve-#{SecureRandom.hex(3)}")
      foreign_store = create(:store, tenant: other_tenant)
      # Estado inconsistente pré-existente: loja de outro tenant persistida no pedido,
      # driblando a validação do model para exercitar o rescue do service.
      request.update_column(:store_id, foreign_store.id)

      result = nil
      expect {
        result = described_class.new(request: request, reviewer: admin).call
      }.not_to raise_error

      expect(result[:success]).to be false
      expect(result[:error]).to eq(:save_failed)
      expect(result[:message]).to be_present
      expect(request.reload).to be_pending
    end
  end
end
