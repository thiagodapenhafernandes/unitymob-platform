require "rails_helper"

RSpec.describe LeadAuditLog, type: :model do
  it "renders human change summaries" do
    log = build(:lead_audit_log, changeset: { "status" => { "before" => "Novo", "after" => "Em Atendimento" } })

    expect(log.change_summaries.first).to include(
      label: "Status",
      before: "Novo",
      after: "Em Atendimento"
    )
  end
end
