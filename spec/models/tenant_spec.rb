require "rails_helper"

RSpec.describe Tenant, type: :model do
  it "cria os perfis verticais fixos Tenant Owner e Agent para toda nova conta" do
    tenant = described_class.create!(name: "Conta Governança #{SecureRandom.hex(3)}")

    owner = tenant.profiles.find_by!(key: "tenant_owner")
    agent = tenant.profiles.find_by!(key: "agent")

    expect(owner).to have_attributes(name: "Tenant Owner", axis: "vertical", position: 0, locked: true)
    expect(owner.permissions).to include("admin" => true)
    expect(agent).to have_attributes(name: "Agent", axis: "vertical", position: 10_000, locked: true)
  end

  it "mantem a criacao dos perfis fixos idempotente" do
    tenant = described_class.create!(name: "Conta Idempotente #{SecureRandom.hex(3)}")

    expect { tenant.ensure_builtin_profiles! }.not_to change { tenant.profiles.count }
  end

  it "resolve tenant publico por slug ativo e preserva default como fallback" do
    tenant = described_class.create!(name: "Conta Publica #{SecureRandom.hex(3)}", slug: "conta-publica-#{SecureRandom.hex(3)}")

    expect(described_class.public_for(slug: tenant.slug)).to eq(tenant)
    expect(described_class.public_for(slug: "inexistente")).to eq(described_class.default)
  end
end
