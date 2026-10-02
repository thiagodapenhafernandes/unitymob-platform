require "rails_helper"

RSpec.describe Proposal, type: :model do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  it "enfileira Purchase com valor ao aceitar proposta de lead Meta" do
    MetaConversionConfig.create!(tenant: tenant, dataset_id: "999")
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok")
    lead = create(:lead, tenant: tenant, attribution_channel: "meta_ads", admin_user: admin)
    proposal = Proposal.create!(lead: lead, admin_user: admin, status: "enviada",
                                title: "Proposta", validade: 5.days.from_now.to_date, valor_cents: 850_000_00)

    expect do
      proposal.decide!("aceita")
    end.to have_enqueued_job(MetaConversionJob).with(tenant.id, lead.id, "Purchase", kind_of(String), kind_of(String), 850000.0)
  end

  it "não enfileira ao recusar nem para lead de outra origem" do
    MetaConversionConfig.create!(tenant: tenant, dataset_id: "999")
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok")
    meta_lead = create(:lead, tenant: tenant, attribution_channel: "meta_ads", admin_user: admin)
    other = create(:lead, tenant: tenant, origin: "site", admin_user: admin)
    refused = Proposal.create!(lead: meta_lead, admin_user: admin, status: "enviada",
                               title: "P1", validade: 5.days.from_now.to_date, valor_cents: 100_00)
    foreign = Proposal.create!(lead: other, admin_user: admin, status: "enviada",
                               title: "P2", validade: 5.days.from_now.to_date, valor_cents: 100_00)

    expect do
      refused.decide!("recusada")
      foreign.decide!("aceita")
    end.not_to have_enqueued_job(MetaConversionJob)
  end
end
