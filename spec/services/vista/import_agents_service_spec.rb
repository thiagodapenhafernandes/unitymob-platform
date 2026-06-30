require "rails_helper"

RSpec.describe Vista::ImportAgentsService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "importa corretor pelo vista_id apenas dentro do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant agentes #{SecureRandom.hex(3)}", slug: "tenant-agentes-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro agentes #{SecureRandom.hex(3)}", slug: "outro-agentes-#{SecureRandom.hex(3)}")
    current_profile = current_tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile, vista_id: "VISTA-10", name: "Outro Tenant")

    Current.tenant = current_tenant
    result = described_class.new.send(
      :process_user,
      {
        "Codigo" => "VISTA-10",
        "Nomecompleto" => "Corretor Tenant Atual",
        "E-mail" => "corretor-atual-#{SecureRandom.hex(4)}@salute.test",
        "Corretor" => "Sim",
        "Inativo" => "Não",
        "Atuaçãoemvenda" => "Sim",
        "Atuaçãoemlocação" => "Não"
      }
    )

    expect(result).to eq(:created)
    expect(current_tenant.admin_users.find_by(vista_id: "VISTA-10").name).to eq("Corretor Tenant Atual")
    expect(other_user.reload.name).to eq("Outro Tenant")
    expect(current_tenant.admin_users.find_by(vista_id: "VISTA-10").profile).to eq(current_profile)
  end

  it "usa perfil vertical customizado do Tenant quando a flag do Vista já está configurada manualmente" do
    tenant = Tenant.create!(name: "Tenant gerente #{SecureRandom.hex(3)}", slug: "tenant-gerente-#{SecureRandom.hex(3)}")
    manager_profile = tenant.profiles.find_by!(key: "gerente")
    Current.tenant = tenant

    result = described_class.new.send(
      :process_user,
      {
        "Codigo" => "VISTA-GER-1",
        "Nomecompleto" => "Gerente Vista",
        "E-mail" => "gerente-vista-#{SecureRandom.hex(4)}@salute.test",
        "Gerente" => "Sim",
        "Corretor" => "Sim",
        "Inativo" => "Não",
        "Atuaçãoemvenda" => "Sim",
        "Atuaçãoemlocação" => "Não"
      }
    )

    expect(result).to eq(:created)
    expect(tenant.admin_users.find_by!(vista_id: "VISTA-GER-1").profile).to eq(manager_profile)
  end

  it "não cria perfil vertical customizado automaticamente quando a flag do Vista não foi configurada" do
    tenant = Tenant.create!(name: "Tenant sem gerente #{SecureRandom.hex(3)}", slug: "tenant-sem-gerente-#{SecureRandom.hex(3)}")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    Current.tenant = tenant

    result = described_class.new.send(
      :process_user,
      {
        "Codigo" => "VISTA-GER-2",
        "Nomecompleto" => "Diretor Sem Perfil",
        "E-mail" => "gerente-sem-perfil-#{SecureRandom.hex(4)}@salute.test",
        "Diretor" => "Sim",
        "Corretor" => "Sim",
        "Inativo" => "Não",
        "Atuaçãoemvenda" => "Sim",
        "Atuaçãoemlocação" => "Não"
      }
    )

    expect(result).to eq(:created)
    expect(tenant.admin_users.find_by!(vista_id: "VISTA-GER-2").profile).to eq(agent_profile)
    expect(tenant.profiles.where(key: "diretor")).not_to exist
    expect(tenant.profiles.where("LOWER(name) = ?", "diretor")).not_to exist
  end

  it "mapeia a flag Administrativo para Gestão Interna com função horizontal" do
    tenant = Tenant.create!(name: "Tenant administrativo #{SecureRandom.hex(3)}", slug: "tenant-administrativo-#{SecureRandom.hex(3)}")
    internal_management_profile = tenant.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME)
    administrative_profile = tenant.profiles.horizontal.find_by!(key: "administrativo")
    Current.tenant = tenant

    result = described_class.new.send(
      :process_user,
      {
        "Codigo" => "VISTA-ADM-1",
        "Nomecompleto" => "Administrativo Vista",
        "E-mail" => "administrativo-vista-#{SecureRandom.hex(4)}@salute.test",
        "Administrativo" => "Sim",
        "Corretor" => "Sim",
        "Inativo" => "Não",
        "Atuaçãoemvenda" => "Sim",
        "Atuaçãoemlocação" => "Não"
      }
    )

    user = tenant.admin_users.find_by!(vista_id: "VISTA-ADM-1")
    expect(result).to eq(:created)
    expect(user.profile).to eq(internal_management_profile)
    expect(user.horizontal_profile).to eq(administrative_profile)
  end
end
