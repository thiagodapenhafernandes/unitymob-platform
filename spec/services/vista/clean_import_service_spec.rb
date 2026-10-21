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

  describe "histórico de entrada e saída dos corretores" do
    let(:tenant) { Tenant.default }
    let(:batch) { build_batch }
    let(:user) { create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "agent"), vista_id: "701", source_created_on: "2018-03-20", source_departed_on: "2024-06-15") }

    def import_agent_row(dates)
      user
      batch.vista_raw_records.create!(table_name: "CADEMP", row_index: 1, payload: {
        "CODIGO_D" => "701", "NOME_COMPLETO" => "Corretor Vista", "CORRETOR" => "Sim"
      }.merge(dates))
      Current.tenant = tenant
      service = described_class.new(batch: batch, dry_run: false)
      service.send(:import_admin_users)
      expect(service.instance_variable_get(:@errors)).to be_empty
      user.reload
    end

    [{}, { "DATA" => "", "DATA_SAIDA" => "0000-00-00" }, { "DATA" => "inválida", "DATA_SAIDA" => "2024-02-31" }].each do |dates|
      it "preserva as datas cadastradas quando a exportação não traz datas válidas: #{dates.inspect}" do
        result = import_agent_row(dates)
        expect(result.source_created_on).to eq(Date.new(2018, 3, 20))
        expect(result.source_departed_on).to eq(Date.new(2024, 6, 15))
      end
    end

    it "não altera datas de outra conta com o mesmo código Vista" do
      other = Tenant.create!(name: "Outra conta datas Vista", slug: "outra-datas-vista-#{SecureRandom.hex(3)}")
      foreign = create(:admin_user, tenant: other, profile: other.profiles.find_by!(key: "agent"), vista_id: "701", source_created_on: "2010-01-01", source_departed_on: "2015-02-01")
      import_agent_row("DATA" => "2019-04-25", "DATA_SAIDA" => "2025-06-16")
      expect(foreign.reload.source_created_on).to eq(Date.new(2010, 1, 1))
      expect(foreign.source_departed_on).to eq(Date.new(2015, 2, 1))
    end

    it "mantém o mapeamento DATA / DATA_SAIDA e o payload bruto do Vista" do
      result = import_agent_row("DATA" => "2019-04-25", "DATA_SAIDA" => "2025-06-16")
      expect(result.source_created_on).to eq(Date.new(2019, 4, 25))
      expect(result.source_departed_on).to eq(Date.new(2025, 6, 16))
      expect(result.vista_payload["DATA"]).to eq("2019-04-25")
    end
  end

end
