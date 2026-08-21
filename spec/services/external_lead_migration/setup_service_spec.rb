require "rails_helper"

RSpec.describe ExternalLeadMigration::SetupService do
  let(:tenant) { Tenant.default }
  let(:admin) { create(:admin_user, :admin, tenant:) }
  let(:broker) { create(:admin_user, tenant:, email: "seller@example.test", name: "Seller Local") }
  let(:owner) { create(:admin_user, :admin, tenant:, email: "owner-externo@example.test", name: "Owner Local") }
  let(:trash_user) { create(:admin_user, tenant:, email: ExternalLeadIntegration::LEGACY_TRASH_LOCAL_EMAIL, name: "Lixeira Conexão BC") }
  let(:integration) { ExternalLeadIntegration.create!(tenant:, access_token: "token-externo", connected_by_admin_user: admin) }
  let(:client) do
    instance_double(
      ExternalLeadMigration::Client,
      me: { "company_id" => "company-1", "company_name" => "Conta externa" },
      sellers: [
        { "id" => "seller-1", "name" => "Seller Externo", "email" => broker.email },
        { "id" => "seller-owner", "name" => "Owner Externo", "email" => owner.email },
        { "id" => "seller-trash", "name" => "Lixeira Conexão BC", "email" => "lixeira_cbc2025@c2sglobal.com" },
        { "id" => "seller-2", "name" => "Sem Par", "email" => "sem-par@example.test" }
      ],
      tags: [{ "id" => "tag-1", "name" => "Praia" }]
    )
  end

  before do
    Current.tenant = tenant
    trash_user
    allow(ExternalLeadMigration::Client).to receive(:new).with(token: "token-externo").and_return(client)
  end

  it "valida token, cria fonte externa e configura regra de distribuicao espelhada" do
    described_class.call(integration:)

    integration.reload
    rule = integration.distribution_rule

    expect(integration).to be_connected
    expect(integration.company_name).to eq("Conta externa")
    expect(integration.seller_mappings).to eq("seller-1" => broker.id, "seller-owner" => owner.id, "seller-trash" => trash_user.id)
    expect(rule).to have_attributes(
      tenant: tenant,
      name: ExternalLeadIntegration::SUPPORT_RULE_NAME,
      source_webhook: true,
      source_site: false,
      source_meta: false,
      source_portal: false
    )
    expect(rule.webhook_tags).to contain_exactly(ExternalLeadIntegration::WEBHOOK_TAG)
    expect(rule.admin_users).to contain_exactly(broker)
    expect(tenant.attribute_options.where(context: "lead", category: "source", name: ExternalLeadIntegration::LEAD_ORIGIN)).to exist
  end
end
