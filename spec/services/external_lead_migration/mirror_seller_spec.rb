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
    renamed = described_class.call(integration:, seller: seller.merge("name" => "Nome atual no C2S"))
    expect(renamed.id).to eq(user.id)
    expect(renamed.name).to eq("Nome atual no C2S")
    expect(renamed).not_to be_active_for_authentication
  end

  it "não cria usuário se o espelhamento estiver desativado" do
    integration.update!(mirror_c2s_owners: false)
    expect { described_class.call(integration:, seller:) }.to raise_error(ArgumentError)
  end

  it "não inventa identidade para um seller sem identificador" do
    expect(described_class.call(integration:, seller: { "name" => "Sem ID" })).to be_nil
  end

  it "não confunde pessoas diferentes que compartilham e-mail ou telefone no legado" do
    unrelated = create(:admin_user, tenant:, name: "Outra Pessoa", email: seller["email"], phone: "47999991234", vista_id: "reused-code")
    integration.update!(seller_mappings: {seller["id"] => unrelated.id})
    user = described_class.call(integration:, seller: seller.merge("phone" => unrelated.phone, "external_id" => "reused-code"))

    expect(user.id).not_to eq(unrelated.id)
    expect(user.name).to eq(seller["name"])
    expect(user).not_to be_active
  end

  it "representa vendedor inativo no C2S sem desativar um usuário local ativo" do
    active = create(:admin_user, tenant:, name: seller["name"], email: seller["email"])
    integration.update!(sellers_payload: [seller.merge("active" => false)], seller_mappings: {seller["id"] => active.id})
    user = described_class.call(integration:, seller:)

    expect(user.id).not_to eq(active.id)
    expect(user).not_to be_active_for_authentication
    expect(active.reload).to be_active
  end
end
