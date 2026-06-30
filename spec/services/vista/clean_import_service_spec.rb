require "rails_helper"

RSpec.describe Vista::CleanImportService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  def build_batch
    VistaImportBatch.create!(dump_dir: "spec", status: "completed")
  end

  it "carrega referencias apenas do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant clean #{SecureRandom.hex(3)}", slug: "tenant-clean-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro clean #{SecureRandom.hex(3)}", slug: "outro-clean-#{SecureRandom.hex(3)}")
    current_profile = current_tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    current_user = create(:admin_user, tenant: current_tenant, profile: current_profile, vista_id: "CLEAN-USER-1")
    create(:admin_user, tenant: other_tenant, profile: other_profile, vista_id: "CLEAN-USER-2")
    current_proprietor = create(:proprietor, tenant: current_tenant, vista_code: "CLEAN-PROP-1")
    create(:proprietor, tenant: other_tenant, vista_code: "CLEAN-PROP-2")
    current_habitation = create(:habitation, tenant: current_tenant, codigo: "CLEAN-HAB-1")
    create(:habitation, tenant: other_tenant, codigo: "CLEAN-HAB-2")

    Current.tenant = current_tenant
    service = described_class.new(batch: build_batch, dry_run: true)
    service.send(:load_reference_ids)

    expect(service.instance_variable_get(:@admin_user_id_by_vista_id)).to eq("CLEAN-USER-1" => current_user.id)
    expect(service.instance_variable_get(:@proprietor_id_by_vista_code)).to eq("CLEAN-PROP-1" => current_proprietor.id)
    expect(service.instance_variable_get(:@habitation_id_by_codigo)).to eq("CLEAN-HAB-1" => current_habitation.id)
  end

  it "valida codigo DWV duplicado apenas dentro do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant clean dwv #{SecureRandom.hex(3)}", slug: "tenant-clean-dwv-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro clean dwv #{SecureRandom.hex(3)}", slug: "outro-clean-dwv-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: other_tenant, codigo: "OUT-CLEAN-DWV", imovel_dwv: "Sim", codigo_dwv: "CLEAN-DWV-1")

    Current.tenant = current_tenant
    service = described_class.new(batch: build_batch, dry_run: true)

    expect(service.send(:unique_dwv_code, "CODIGO" => "CUR-CLEAN-DWV", "CODIGO_DWV" => "CLEAN-DWV-1")).to eq("CLEAN-DWV-1")
  end

  it "usa perfil customizado existente para cargo Vista sem criar níveis automaticamente" do
    tenant = Tenant.create!(name: "Tenant clean perfil #{SecureRandom.hex(3)}", slug: "tenant-clean-perfil-#{SecureRandom.hex(3)}")
    manager_profile = tenant.profiles.find_by!(key: "gerente")
    Current.tenant = tenant
    service = described_class.new(batch: build_batch, dry_run: true)

    expect(service.send(:profile_for_agent, "GERENTE" => "Sim", "CORRETOR" => "Sim")).to eq(manager_profile)
  end

  it "cai em Agent quando cargo Vista não possui perfil manual configurado" do
    tenant = Tenant.create!(name: "Tenant clean agent #{SecureRandom.hex(3)}", slug: "tenant-clean-agent-#{SecureRandom.hex(3)}")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    Current.tenant = tenant
    service = described_class.new(batch: build_batch, dry_run: true)

    expect(service.send(:profile_for_agent, "DIRETOR" => "Sim", "CORRETOR" => "Sim")).to eq(agent_profile)
    expect(service.send(:role_for_agent, "DIRETOR" => "Sim")).to eq("editor")
    expect(tenant.profiles.where(key: "diretor")).not_to exist
  end

  it "mapeia CADUSU para Gestão Interna e função horizontal Administrativo" do
    tenant = Tenant.create!(name: "Tenant clean administrativo #{SecureRandom.hex(3)}", slug: "tenant-clean-administrativo-#{SecureRandom.hex(3)}")
    internal_management_profile = tenant.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME)
    administrative_profile = tenant.profiles.horizontal.find_by!(key: "administrativo")
    Current.tenant = tenant
    service = described_class.new(batch: build_batch, dry_run: true)

    row = { "CADUSU" => "Sim", "CORRETOR" => "Sim" }

    expect(service.send(:profile_for_agent, row)).to eq(internal_management_profile)
    expect(service.send(:horizontal_profile_for_agent, row)).to eq(administrative_profile)
  end
end
