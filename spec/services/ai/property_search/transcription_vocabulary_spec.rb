require "rails_helper"

RSpec.describe Ai::PropertySearch::TranscriptionVocabulary do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant: tenant) }
  let(:setting) { PropertySetting.instance(tenant: tenant) }

  it "monta o vocabulário com cidades, bairros e empreendimentos do tenant" do
    habitation = create(:habitation, tenant:, admin_user: broker, cidade: "Itapema", codigo: "VOCAB-1")
    habitation.address.update!(cidade: "Itapema", bairro: "Meia Praia")
    create(:habitation, tenant:, tipo: "Empreendimento", nome_empreendimento: "Residencial Vocabulário", codigo: "VOCAB-DEV")

    prompt = described_class.new(tenant:, setting:).call

    expect(prompt).to start_with("Vocabulário: ")
    expect(prompt).to include("Itapema", "Meia Praia", "Residencial Vocabulário")
    expect(prompt.length).to be <= described_class::MAX_CHARS + 1
  end

  it "não inclui nomes de outros tenants" do
    outside_tenant = Tenant.create!(name: "Vocab #{SecureRandom.hex(3)}", slug: "vocab-#{SecureRandom.hex(3)}")
    outsider = create(:habitation, tenant: outside_tenant, cidade: "Cidade Sigilosa", codigo: "VOCAB-OUT")
    outsider.address.update!(cidade: "Cidade Sigilosa", bairro: "Bairro Sigiloso")
    create(:habitation, tenant:, admin_user: broker, cidade: "Itapema", codigo: "VOCAB-IN")

    prompt = described_class.new(tenant:, setting:).call.to_s

    expect(prompt).not_to include("Cidade Sigilosa", "Bairro Sigiloso")
  end

  it "retorna nil quando o tenant não tem dados" do
    empty_tenant = Tenant.create!(name: "Vazio #{SecureRandom.hex(3)}", slug: "vazio-#{SecureRandom.hex(3)}")

    expect(described_class.new(tenant: empty_tenant, setting:).call).to be_nil
  end
end
