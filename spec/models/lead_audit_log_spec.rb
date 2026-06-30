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

  it "não resolve nomes de usuários, imóveis ou regras de outro Tenant no changeset" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: profile, name: "Usuário Externo")
    other_habitation = create(:habitation, tenant: other_tenant, codigo: "HAB-EXTERNO")
    other_rule = create(:distribution_rule, tenant: other_tenant, name: "Regra Externa")
    lead = create(:lead, tenant: tenant)
    log = build(
      :lead_audit_log,
      tenant: tenant,
      lead: lead,
      admin_user: nil,
      changeset: {
        "admin_user_id" => { "before" => nil, "after" => other_user.id },
        "property_id" => { "before" => nil, "after" => other_habitation.id },
        "distribution_rule_id" => { "before" => nil, "after" => other_rule.id }
      }
    )

    summaries = log.change_summaries

    expect(summaries.map { |summary| summary[:after] }).to include(
      "Usuário ##{other_user.id}",
      "Imóvel ##{other_habitation.id}",
      "Regra ##{other_rule.id}"
    )
    expect(summaries.map { |summary| summary[:after] }).not_to include("Usuário Externo", "HAB-EXTERNO", "Regra Externa")
  end
end
