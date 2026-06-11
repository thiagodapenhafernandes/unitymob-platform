require 'rails_helper'

RSpec.describe "Admin::Field::CheckIns", type: :request do
  let(:admin) { create(:admin_user, :admin) }
  let(:agent) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }
  let!(:check_in) { create(:check_in, admin_user: agent, store: store, status: :active) }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "POST /admin/field/check_ins/:id/force_check_out" do
    it "fecha o check-in com status closed_admin_force e audita como forced_closed" do
      expect {
        post "/admin/field/check_ins/#{check_in.id}/force_check_out"
      }.to change { CheckinAuditLog.where(action: "forced_closed").count }.by(1)

      expect(check_in.reload.status).to eq("closed_admin_force")
    end
  end

  private

  def sign_in(admin_user)
    post "/admin/sign_in", params: { admin_user: { email: admin_user.email, password: "password123" } }
  end
end
