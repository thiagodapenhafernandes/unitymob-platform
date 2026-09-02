require "rails_helper"

RSpec.describe MetaSyncEnabledIntegrationsJob, type: :job do
  around do |example|
    Lead.skip_callback(:commit, :after, :route_lead)
    example.run
  ensure
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "agenda sincronizacao das integracoes Meta ativas" do
    tenant = Tenant.create!(name: "Conta Meta Sync #{SecureRandom.hex(3)}", slug: "conta-meta-sync-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    expired_admin = create(:admin_user, :admin, tenant: tenant)
    processing_admin = create(:admin_user, :admin, tenant: tenant)
    syncable = create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "token-ok")
    create(:user_meta_integration, admin_user: expired_admin, tenant: tenant, access_token: "token-expired", token_expires_at: 1.minute.ago)
    create(:user_meta_integration, admin_user: processing_admin, tenant: tenant, access_token: "token-processing", sync_status: "processing", updated_at: 5.minutes.ago)

    allow(MetaSyncJob).to receive(:perform_later)

    described_class.perform_now

    expect(MetaSyncJob).to have_received(:perform_later).with(syncable.id).once
  end

  it "inclui na regra forms observados em leads antes da sincronizacao da Meta" do
    tenant = Tenant.create!(name: "Conta Meta Observada #{SecureRandom.hex(3)}", slug: "conta-meta-observada-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "token-ok")
    create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-observed", access_token: "page-token")
    rule = create(
      :distribution_rule,
      tenant: tenant,
      source_meta: true,
      source_site: false,
      auto_add_forms: true,
      meta_page_ids: ["page-observed"],
      meta_forms: []
    )
    create(
      :lead,
      tenant: tenant,
      origin: "Facebook Lead Ads",
      other_information: {
        "meta_page_id" => "page-observed",
        "meta_form_id" => "form-observed"
      }
    )

    allow(MetaSyncJob).to receive(:perform_later)

    described_class.perform_now

    expect(rule.reload.meta_forms).to include("form-observed")
    expect(MetaLeadForm.find_by(form_id: "form-observed", meta_facebook_page_id: integration.meta_facebook_pages.first.id)).to be_present
  end
end
