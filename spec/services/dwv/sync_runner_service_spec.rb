require "rails_helper"

RSpec.describe Dwv::SyncRunnerService do
  describe "sincronização incremental" do
    it "consulta apenas alterações do dia informado e importa os imóveis retornados" do
      current_tenant = Tenant.create!(name: "Tenant incremental DWV #{SecureRandom.hex(3)}", slug: "tenant-incremental-dwv-#{SecureRandom.hex(3)}")
      Current.tenant = current_tenant
      Setting.set("dwv_enabled", "true", "teste", tenant: current_tenant)
      Setting.set("dwv_api_token", "token-dwv", "teste", tenant: current_tenant)

      client = instance_double(Dwv::Client)
      service = described_class.new(tenant: current_tenant)
      status_service = instance_double(Dwv::SyncStatusService, mark_processing!: true, update_progress!: true)
      details = { "id" => "DWV-INC-1" }
      importer = instance_double(Dwv::PropertyImportService, perform: { success: true })

      allow(service).to receive(:build_client).and_return(client)
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false, last_updates: "2026-07-07,2026-07-07").and_return({ "data" => [{ "id" => "DWV-INC-1" }] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false).and_return({ "data" => [{ "id" => "DWV-INC-1" }] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: true, last_updates: "2026-07-07,2026-07-07").and_return({ "data" => [] })
      allow(client).to receive(:property_details).with("DWV-INC-1").and_return(details)
      allow(Dwv::PropertyImportService).to receive(:new).with(details, tenant: current_tenant).and_return(importer)

      result = service.call(mode: "incremental", limit: 50, max_pages: 1, last_updates: "07/07/2026", status_service: status_service)

      expect(result).to include(imported: 1, deactivated: 0, errors_count: 0)
      expect(Dwv::PropertyImportService).to have_received(:new).with(details, tenant: current_tenant)
    end

    it "importa imóvel ativo ausente localmente mesmo quando o filtro incremental não retorna alterações" do
      current_tenant = Tenant.create!(name: "Tenant active missing DWV #{SecureRandom.hex(3)}", slug: "tenant-active-missing-dwv-#{SecureRandom.hex(3)}")
      Current.tenant = current_tenant
      Setting.set("dwv_enabled", "true", "teste", tenant: current_tenant)
      Setting.set("dwv_api_token", "token-dwv", "teste", tenant: current_tenant)

      client = instance_double(Dwv::Client)
      service = described_class.new(tenant: current_tenant)
      status_service = instance_double(Dwv::SyncStatusService, mark_processing!: true, update_progress!: true)
      details = { "id" => "653408" }
      importer = instance_double(Dwv::PropertyImportService, perform: { success: true })

      allow(service).to receive(:build_client).and_return(client)
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false, last_updates: "2026-07-21,2026-07-21").and_return({ "data" => [] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false).and_return({ "data" => [{ "id" => "653408" }] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: true, last_updates: "2026-07-21,2026-07-21").and_return({ "data" => [] })
      allow(client).to receive(:property_details).with("653408").and_return(details)
      allow(Dwv::PropertyImportService).to receive(:new).with(details, tenant: current_tenant).and_return(importer)

      result = service.call(mode: "incremental", limit: 50, max_pages: 1, last_updates: "21/07/2026", status_service: status_service)

      expect(result).to include(imported: 1, deactivated: 0, errors_count: 0)
      expect(Dwv::PropertyImportService).to have_received(:new).with(details, tenant: current_tenant)
    end

    it "remove imóvel DWV local que desapareceu da lista ativa durante o incremental" do
      current_tenant = Tenant.create!(name: "Tenant incremental removed DWV #{SecureRandom.hex(3)}", slug: "tenant-incremental-removed-dwv-#{SecureRandom.hex(3)}")
      Current.tenant = current_tenant
      Setting.set("dwv_enabled", "true", "teste", tenant: current_tenant)
      Setting.set("dwv_api_token", "token-dwv", "teste", tenant: current_tenant)
      kept_habitation = create(:habitation, tenant: current_tenant, codigo: "DWV-KEPT", codigo_dwv: "DWV-KEPT", imovel_dwv: "Sim", status: "Venda", exibir_no_site_flag: true)
      removed_habitation = create(:habitation, tenant: current_tenant, codigo: "DWV-GONE", codigo_dwv: "DWV-GONE", imovel_dwv: "Sim", status: "Venda", exibir_no_site_flag: true)

      client = instance_double(Dwv::Client)
      service = described_class.new(tenant: current_tenant)
      status_service = instance_double(Dwv::SyncStatusService, mark_processing!: true, update_progress!: true)

      allow(service).to receive(:build_client).and_return(client)
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false, last_updates: "2026-07-21,2026-07-21").and_return({ "data" => [] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false).and_return({ "data" => [{ "id" => "DWV-KEPT" }] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: true, last_updates: "2026-07-21,2026-07-21").and_return({ "data" => [] })

      result = service.call(mode: "incremental", limit: 50, max_pages: 1, last_updates: "21/07/2026", status_service: status_service)

      expect(result).to include(imported: 0, deactivated: 1, errors_count: 0)
      expect(current_tenant.habitations.where(id: kept_habitation.id)).to exist
      expect(current_tenant.habitations.where(id: removed_habitation.id)).not_to exist
    end

    it "importa imóvel de locação ativo que ainda não existe localmente" do
      current_tenant = Tenant.create!(name: "Tenant incremental rent DWV #{SecureRandom.hex(3)}", slug: "tenant-incremental-rent-dwv-#{SecureRandom.hex(3)}")
      Current.tenant = current_tenant
      Setting.set("dwv_enabled", "true", "teste", tenant: current_tenant)
      Setting.set("dwv_api_token", "token-dwv", "teste", tenant: current_tenant)

      client = instance_double(Dwv::Client)
      service = described_class.new(tenant: current_tenant)
      status_service = instance_double(Dwv::SyncStatusService, mark_processing!: true, update_progress!: true)
      details = { "id" => "DWV-RENT", "unit" => { "rent" => true, "price" => nil }, "rent_price" => "12000.00" }
      importer = instance_double(Dwv::PropertyImportService, perform: { success: true })

      allow(service).to receive(:build_client).and_return(client)
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false, last_updates: "2026-07-21,2026-07-21").and_return({ "data" => [] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false).and_return({ "data" => [{ "id" => "DWV-RENT", "unit" => { "rent" => true } }] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: true, last_updates: "2026-07-21,2026-07-21").and_return({ "data" => [] })
      allow(client).to receive(:property_details).with("DWV-RENT").and_return(details)
      allow(Dwv::PropertyImportService).to receive(:new).with(details, tenant: current_tenant).and_return(importer)

      result = service.call(mode: "incremental", limit: 50, max_pages: 1, last_updates: "21/07/2026", status_service: status_service)

      expect(result).to include(imported: 1, deactivated: 0, errors_count: 0)
      expect(Dwv::PropertyImportService).to have_received(:new).with(details, tenant: current_tenant)
    end
  end

  describe "sincronização full" do
    it "consulta imóveis ativos explicitamente com deleted=false" do
      current_tenant = Tenant.create!(name: "Tenant full DWV #{SecureRandom.hex(3)}", slug: "tenant-full-dwv-#{SecureRandom.hex(3)}")
      Current.tenant = current_tenant
      Setting.set("dwv_enabled", "true", "teste", tenant: current_tenant)
      Setting.set("dwv_api_token", "token-dwv", "teste", tenant: current_tenant)

      client = instance_double(Dwv::Client)
      service = described_class.new(tenant: current_tenant)
      status_service = instance_double(Dwv::SyncStatusService, mark_processing!: true, update_progress!: true)
      details = { "id" => "DWV-FULL-1" }
      importer = instance_double(Dwv::PropertyImportService, perform: { success: true })

      allow(service).to receive(:build_client).and_return(client)
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false).and_return({ "data" => [{ "id" => "DWV-FULL-1" }] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: true).and_return({ "data" => [] })
      allow(client).to receive(:property_details).with("DWV-FULL-1").and_return(details)
      allow(Dwv::PropertyImportService).to receive(:new).with(details, tenant: current_tenant).and_return(importer)

      result = service.call(mode: "full", limit: 50, max_pages: 1, status_service: status_service)

      expect(result).to include(imported: 1, deactivated: 0, errors_count: 0)
      expect(client).to have_received(:list_properties).with(limit: 50, page: 1, deleted: false).twice
    end

    it "remove imóvel DWV local que não aparece mais na lista ativa" do
      current_tenant = Tenant.create!(name: "Tenant missing DWV #{SecureRandom.hex(3)}", slug: "tenant-missing-dwv-#{SecureRandom.hex(3)}")
      Current.tenant = current_tenant
      Setting.set("dwv_enabled", "true", "teste", tenant: current_tenant)
      Setting.set("dwv_api_token", "token-dwv", "teste", tenant: current_tenant)
      missing_habitation = create(:habitation, tenant: current_tenant, codigo: "DWV-MISSING", codigo_dwv: "DWV-MISSING", imovel_dwv: "Sim", exibir_no_site_flag: true)

      client = instance_double(Dwv::Client)
      service = described_class.new(tenant: current_tenant)
      status_service = instance_double(Dwv::SyncStatusService, mark_processing!: true, update_progress!: true)

      allow(service).to receive(:build_client).and_return(client)
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: false).and_return({ "data" => [] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: true).and_return({ "data" => [] })

      result = service.call(mode: "full", limit: 50, max_pages: 1, status_service: status_service)

      expect(result).to include(imported: 0, deactivated: 1, errors_count: 0)
      expect(current_tenant.habitations.where(id: missing_habitation.id)).not_to exist
    end
  end

  describe "remoção de removidos" do
    it "remove imóveis DWV apenas no tenant informado" do
      current_tenant = Tenant.create!(name: "Tenant runner DWV #{SecureRandom.hex(3)}", slug: "tenant-runner-dwv-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro runner DWV #{SecureRandom.hex(3)}", slug: "outro-runner-dwv-#{SecureRandom.hex(3)}")
      current_habitation = create(:habitation, tenant: current_tenant, codigo: "CUR-RUN-DWV", codigo_dwv: "DWV-RUN-1", imovel_dwv: "Sim", status: "Venda", exibir_no_site_flag: true)
      other_habitation = create(:habitation, tenant: other_tenant, codigo: "OUT-RUN-DWV", codigo_dwv: "DWV-RUN-1", imovel_dwv: "Sim", status: "Venda", exibir_no_site_flag: true)

      result = described_class.new(tenant: current_tenant).send(:destroy_removed_properties_by_ids, ["DWV-RUN-1"])

      expect(result).to eq(1)
      expect(current_tenant.habitations.where(id: current_habitation.id)).not_to exist
      expect(other_habitation.reload).to have_attributes(status: "Venda", exibir_no_site_flag: true, last_sync_status: nil)
    end

    it "desvincula referências opcionais que bloqueiam FK antes de remover o imóvel" do
      current_tenant = Tenant.create!(name: "Tenant refs DWV #{SecureRandom.hex(3)}", slug: "tenant-refs-dwv-#{SecureRandom.hex(3)}")
      Current.tenant = current_tenant
      admin_user = create(:admin_user, tenant: current_tenant)
      habitation = create(:habitation, tenant: current_tenant, codigo: "DWV-REFS", codigo_dwv: "DWV-REFS", imovel_dwv: "Sim", status: "Venda", exibir_no_site_flag: true)
      batch = VistaImportBatch.create!(dump_dir: "spec/dwv/#{SecureRandom.hex(4)}", status: "completed")
      vista_file_asset = VistaFileAsset.create!(
        vista_import_batch: batch,
        habitation: habitation,
        table_name: "imoveis",
        kind: "property_photo",
        source_path: "dwv/#{habitation.codigo}/foto.jpg",
        filename: "foto.jpg",
        status: "downloaded"
      )
      seo_event = SeoConversionEvent.create!(
        habitation: habitation,
        event_type: "property_card_click",
        occurred_at: Time.current
      )
      interaction = HabitationInteraction.create!(
        habitation: habitation,
        source_table: "DWV",
        source_key: "DWV-REFS-#{SecureRandom.hex(4)}"
      )
      broker_assignment = HabitationBrokerAssignment.create!(
        habitation: habitation,
        admin_user: admin_user,
        role: "captador",
        commission_type: "percentage"
      )
      share_link = HabitationShareLink.create!(habitation: habitation, admin_user: admin_user)

      result = described_class.new(tenant: current_tenant).send(:destroy_removed_properties_by_ids, ["DWV-REFS"])

      expect(result).to eq(1)
      expect(current_tenant.habitations.where(id: habitation.id)).not_to exist
      expect(vista_file_asset.reload.habitation_id).to be_nil
      expect(seo_event.reload.habitation_id).to be_nil
      expect(interaction.reload.habitation_id).to be_nil
      expect(HabitationBrokerAssignment.where(id: broker_assignment.id)).not_to exist
      expect(HabitationShareLink.where(id: share_link.id)).not_to exist
    end
  end
end
