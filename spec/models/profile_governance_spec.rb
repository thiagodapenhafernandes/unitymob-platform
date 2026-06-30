require "rails_helper"

RSpec.describe Profile, "governança vertical/horizontal", type: :model do
  let(:tenant) { Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}") }

  it "mantém Tenant Owner no topo da hierarquia vertical" do
    profile = tenant.profiles.find_by!(key: "tenant_owner")
    profile.update!(position: 500, locked: false)

    expect(profile).to be_vertical
    expect(profile).to be_locked
    expect(profile.position).to eq(0)
    expect(profile).to be_admin
  end

  it "mantém Agent como último perfil vertical fixo" do
    profile = tenant.profiles.find_by!(key: "agent")
    profile.update!(position: 10, locked: false)

    expect(profile).to be_vertical
    expect(profile).to be_locked
    expect(profile.position).to eq(10_000)
  end

  it "permite perfil vertical customizado entre Tenant Owner e Agent" do
    profile = described_class.create!(
      tenant: tenant,
      name: "Director",
      axis: "vertical",
      position: 150,
      permissions: { "leads" => { "view" => true, "scope" => "team" } }
    )

    expect(profile).to be_vertical
    expect(profile).not_to be_locked
    expect(profile.position).to eq(150)
  end

  it "bloqueia perfil vertical customizado fora do intervalo entre Tenant Owner e Agent" do
    before_owner = described_class.new(tenant: tenant, name: "Acima do owner", axis: "vertical", position: 0, permissions: {})
    after_agent = described_class.new(tenant: tenant, name: "Abaixo do agent", axis: "vertical", position: 10_000, permissions: {})

    expect(before_owner).not_to be_valid
    expect(before_owner.errors[:position]).to be_present
    expect(after_agent).not_to be_valid
    expect(after_agent.errors[:position]).to be_present
  end

  it "não permite dois perfis verticais na mesma posição dentro do Tenant" do
    described_class.create!(tenant: tenant, name: "Director", axis: "vertical", position: 150, permissions: {})
    duplicated = described_class.new(tenant: tenant, name: "Superintendent", axis: "vertical", position: 150, permissions: {})

    expect(duplicated).not_to be_valid
    expect(duplicated.errors[:position]).to be_present
  end

  it "usa chaves canônicas mesmo quando nomes legados são informados" do
    owner = tenant.profiles.find_by!(key: "tenant_owner")
    agent = tenant.profiles.find_by!(key: "agent")

    expect(owner.key).to eq("tenant_owner")
    expect(owner.position).to eq(0)
    expect(agent.key).to eq("agent")
    expect(agent.position).to eq(10_000)
  end

  it "exige que perfil horizontal esteja anexado a um perfil vertical do mesmo Tenant" do
    vertical = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})

    horizontal = described_class.create!(
      tenant: tenant,
      name: "Support",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: { "whatsapp_inbox" => { "view" => true, "scope" => "own" } }
    )

    expect(horizontal).to be_horizontal
    expect(horizontal.vertical_profile).to eq(vertical)
    expect(horizontal.position).to be_nil
  end

  it "não permite perfil horizontal sem perfil vertical" do
    profile = described_class.new(tenant: tenant, name: "Finance", axis: "horizontal", permissions: {})

    expect(profile).not_to be_valid
    expect(profile.errors[:vertical_profile]).to be_present
  end

  it "permite converter o eixo de um perfil não fixo quando a nova forma é válida" do
    profile = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})

    profile.axis = "horizontal"
    profile.vertical_profile = tenant.profiles.find_by!(key: "tenant_owner")

    expect(profile).to be_valid
  end

  it "permite mover uma função horizontal para outro perfil vertical" do
    manager = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    director = described_class.create!(tenant: tenant, name: "Director", axis: "vertical", position: 150, permissions: {})
    horizontal = described_class.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: manager, permissions: {})

    horizontal.vertical_profile = director

    expect(horizontal).to be_valid
  end

  it "mantém apenas Tenant Owner e Agent como perfis fixos de eixo vertical" do
    owner = tenant.profiles.find_by!(key: "tenant_owner")
    agent = tenant.profiles.find_by!(key: "agent")

    owner.axis = "horizontal"
    owner.vertical_profile = described_class.create!(tenant: tenant, name: "Manager owner test", axis: "vertical", position: 200, permissions: {})
    agent.axis = "horizontal"
    agent.vertical_profile = owner.vertical_profile

    expect(owner).not_to be_valid
    expect(agent).not_to be_valid
    expect(owner.errors[:axis]).to be_present
    expect(agent.errors[:axis]).to be_present
  end

  it "bloqueia no banco perfis com eixo ou forma incompatível" do
    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Eixo inválido",
          axis: "diagonal",
          position: 500,
          permissions: {},
          active: true,
          locked: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Horizontal com posição",
          axis: "horizontal",
          vertical_profile_id: tenant.profiles.find_by!(key: "agent").id,
          position: 500,
          permissions: {},
          active: true,
          locked: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco função horizontal anexada a outro perfil horizontal" do
    vertical = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    horizontal = described_class.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: vertical, permissions: {})

    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Auditor inválido",
          axis: "horizontal",
          vertical_profile_id: horizontal.id,
          position: nil,
          permissions: {},
          active: true,
          locked: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco posições verticais fora da governança do Tenant" do
    common = {
      tenant_id: tenant.id,
      axis: "vertical",
      vertical_profile_id: nil,
      permissions: {},
      active: true,
      created_at: Time.current,
      updated_at: Time.current
    }

    expect {
      described_class.insert_all!([
        common.merge(
          name: "Owner fora do topo",
          key: "tenant_owner",
          position: 500,
          locked: true
        )
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      described_class.insert_all!([
        common.merge(
          name: "Custom abaixo do Agent",
          key: nil,
          position: 10_000,
          locked: false
        )
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      described_class.insert_all!([
        common.merge(
          name: "Custom travado",
          key: nil,
          position: 500,
          locked: true
        )
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco Agent deslocado para qualquer posição diferente de 10000" do
    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Agent abaixo do último nível",
          key: "agent",
          axis: "vertical",
          vertical_profile_id: nil,
          position: 10_001,
          permissions: {},
          active: true,
          locked: true,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "restringe o escopo horizontal ao limite vertical" do
    expect(described_class.restricted_scope("team", "all")).to eq("team")
    expect(described_class.restricted_scope("team", "own")).to eq("own")
    expect(described_class.restricted_scope("all", "team")).to eq("team")
    expect(described_class.restricted_scope("team", nil)).to eq("team")
  end

  it "permite configurar escopo hierárquico nos recursos de auditoria" do
    resources = described_class::RESOURCES.index_by { |resource| resource.fetch(:key) }

    expect(resources.fetch("field_audit")).to include(scopeable: true)
    expect(resources.fetch("access_audit")).to include(scopeable: true)
    expect(resources.fetch("data_export_audit")).to include(scopeable: true)
    expect(resources.fetch("access_security")).to include(scopeable: true)
  end
end
