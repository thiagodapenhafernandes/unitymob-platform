require "rails_helper"

RSpec.describe Profile, "papel estável por key (rename-safe)", type: :model do
  it "atribui o key canônico ao criar um perfil de sistema pelo nome" do
    tenant = Tenant.create!(name: "Tenant keys #{SecureRandom.hex(3)}")

    expect(tenant.profiles.find_by!(key: "tenant_owner").name).to eq("Tenant Owner")
    expect(tenant.profiles.find_by!(key: "agent").name).to eq("Agent")
  end

  it "não atribui key a perfis customizados" do
    tenant = Tenant.create!(name: "Tenant custom #{SecureRandom.hex(3)}")
    expect(Profile.create!(tenant: tenant, name: "Supervisor Regional").key).to be_nil
    expect(Profile.create!(tenant: tenant, name: "Diretor").key).to be_nil
  end

  it "atribui keys canônicas para Gerente vertical e Administrativo horizontal" do
    tenant = Tenant.create!(name: "Tenant admin horizontal #{SecureRandom.hex(3)}")
    internal_management = tenant.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME)
    manager = tenant.profiles.find_by!(key: "gerente")
    administrative = tenant.profiles.find_by!(key: "administrativo")

    expect(internal_management).to be_vertical
    expect(internal_management.position).to be_between(1, 9_999)
    expect(manager).to be_vertical
    expect(administrative).to be_horizontal
    expect(administrative.vertical_profile).to eq(internal_management)
  end

  it "predicados de papel seguem o key, não o nome" do
    tenant = Tenant.create!(name: "Tenant predicates #{SecureRandom.hex(3)}")
    admin = tenant.profiles.find_by!(key: "tenant_owner")
    adm = tenant.profiles.find_by!(key: "administrativo")

    expect(admin.admin?).to be(true)
    expect(adm.administrativo?).to be(true)
    expect(adm.admin?).to be(false)
  end

  it "renomear um perfil com key manual preserva o comportamento" do
    tenant = Tenant.create!(name: "Tenant rename #{SecureRandom.hex(3)}")
    profile = tenant.profiles.find_by!(key: "administrativo")
    profile.update!(name: "Equipe Interna")

    expect(profile.reload.key).to eq("administrativo")
    expect(profile.administrativo?).to be(true)
    expect(profile.name).to eq("Equipe Interna")
  end

  it "admin? não é concedido por flag solta fora do Tenant Owner" do
    tenant = Tenant.create!(name: "Tenant custom admin #{SecureRandom.hex(3)}")
    custom = Profile.create!(tenant: tenant, name: "Super", permissions: { "admin" => true })
    expect(custom.key).to be_nil
    expect(custom.admin?).to be(false)
    expect(custom.full_access?).to be(true)
    expect(custom.can?(:manage, :leads)).to be(true)
    expect(custom.scope_for(:leads)).to eq("all")
  end

  it "não duplica key quando o nome canônico já está em uso por outro perfil" do
    tenant = Tenant.create!(name: "Tenant duplicate #{SecureRandom.hex(3)}")
    Profile.create!(tenant: tenant, name: "Corretor")
    other = Profile.create!(tenant: tenant, name: "Corretor Comercial")
    expect(tenant.profiles.where(key: "agent").count).to eq(1)
    expect(other.key).to be_nil
  end
end
