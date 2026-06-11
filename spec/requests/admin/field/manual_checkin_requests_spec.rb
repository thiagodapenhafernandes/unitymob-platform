require 'rails_helper'

RSpec.describe "Admin::Field::ManualCheckinRequests", type: :request do
  let(:admin) { create(:admin_user, :admin) }
  let(:agent) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }
  let!(:request_record) { create(:manual_checkin_request, admin_user: agent, store: store) }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "POST approve" do
    it "cria check-in manual ativo + audita + marca request aprovada" do
      expect {
        post "/admin/field/manual_checkin_requests/#{request_record.id}/approve",
             params: { review_notes: "ok" }
      }.to change { CheckIn.where(admin_user: agent, status: :active).count }.by(1)

      request_record.reload
      expect(request_record).to be_approved
      expect(request_record.reviewed_by_admin_user).to eq(admin)

      ci = agent.active_check_in
      expect(ci.device_info["manual"]).to be true
    end
  end

  describe "POST reject" do
    it "marca como rejeitada + audita" do
      expect {
        post "/admin/field/manual_checkin_requests/#{request_record.id}/reject",
             params: { review_notes: "sem evidência" }
      }.to change { CheckinAuditLog.where(action: "manual_request_rejected").count }.by(1)

      expect(request_record.reload).to be_rejected
    end
  end

  private

  def sign_in(admin_user)
    post "/admin/sign_in", params: { admin_user: { email: admin_user.email, password: "password123" } }
  end
end
