require "rails_helper"

RSpec.describe ExternalLeadMigration::MirrorSeller do
  let(:tenant) { Tenant.default }
  let(:integration) { create(:external_lead_integration, tenant:, operational_mappings: { "mirror_c2s_owners" => true }) }
  let(:seller) { { "id" => "historical-42", "name" => "Corretor Histórico", "email" => "antigo@example.test" } }

  it "cria uma única referência inativa e registra o vínculo sem usar o e-mail externo como login" do
    user = described_class.call(integration:, seller:)
    expect { described_class.call(integration:, seller:) }.not_to change(AdminUser, :count)
    expect(user).to have_attributes(tenant_id: tenant.id, active: false, super_admin: false, role: "editor")
    expect(user).not_to be_active_for_authentication
    expect(user.email).to end_with("@reference.invalid")
    expect(user.email).not_to eq(seller["email"])
    expect(integration.reload.seller_mappings[seller["id"]]).to eq(user.id)
  end

  it "não cria usuário se o espelhamento estiver desativado" do
    integration.update!(mirror_c2s_owners: false)
    expect { described_class.call(integration:, seller:) }.to raise_error(ArgumentError)
  end

  it "não inventa identidade para um seller sem identificador" do
    expect(described_class.call(integration:, seller: { "name" => "Sem ID" })).to be_nil
  end
end
