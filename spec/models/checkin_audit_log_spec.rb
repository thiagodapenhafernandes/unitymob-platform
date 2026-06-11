require 'rails_helper'

RSpec.describe CheckinAuditLog do
  let(:user) { create(:admin_user, :field_agent) }
  let(:store) { create(:store) }
  let(:check_in) { create(:check_in, admin_user: user, store: store, status: :active) }

  describe "criação via .log!" do
    it "persiste com action válida" do
      log = CheckinAuditLog.log!(action: "created", check_in: check_in, metadata: { foo: "bar" })
      expect(log.persisted?).to be true
      expect(log.admin_user_id).to eq(user.id)
      expect(log.metadata["foo"]).to eq("bar")
    end

    it "rejeita action inválida" do
      expect {
        CheckinAuditLog.log!(action: "not_an_action", check_in: check_in)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "append-only (trigger PG)" do
    let!(:log) { CheckinAuditLog.log!(action: "created", check_in: check_in) }

    it "rejeita UPDATE no banco" do
      expect {
        ActiveRecord::Base.connection.execute(
          "UPDATE checkin_audit_logs SET action = 'closed' WHERE id = #{log.id}"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    end

    it "rejeita DELETE no banco" do
      expect {
        ActiveRecord::Base.connection.execute("DELETE FROM checkin_audit_logs WHERE id = #{log.id}")
      }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    end

    it "marca o record como readonly? via Rails" do
      expect(log.readonly?).to be true
    end
  end
end
