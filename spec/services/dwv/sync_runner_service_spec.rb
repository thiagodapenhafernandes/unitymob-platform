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
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: nil, last_updates: "2026-07-07,2026-07-07").and_return({ "data" => [{ "id" => "DWV-INC-1" }] })
      allow(client).to receive(:list_properties).with(limit: 50, page: 1, deleted: true, last_updates: "2026-07-07,2026-07-07").and_return({ "data" => [] })
      allow(client).to receive(:property_details).with("DWV-INC-1").and_return(details)
      allow(Dwv::PropertyImportService).to receive(:new).with(details, tenant: current_tenant).and_return(importer)

      result = service.call(mode: "incremental", limit: 50, max_pages: 1, last_updates: "07/07/2026", status_service: status_service)

      expect(result).to include(imported: 1, deactivated: 0, errors_count: 0)
      expect(Dwv::PropertyImportService).to have_received(:new).with(details, tenant: current_tenant)
    end
  end

  describe "desativação de removidos" do
    it "desativa imóveis DWV apenas no tenant informado" do
      current_tenant = Tenant.create!(name: "Tenant runner DWV #{SecureRandom.hex(3)}", slug: "tenant-runner-dwv-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro runner DWV #{SecureRandom.hex(3)}", slug: "outro-runner-dwv-#{SecureRandom.hex(3)}")
      current_habitation = create(:habitation, tenant: current_tenant, codigo: "CUR-RUN-DWV", codigo_dwv: "DWV-RUN-1", imovel_dwv: "Sim", status: "Venda", exibir_no_site_flag: true)
      other_habitation = create(:habitation, tenant: other_tenant, codigo: "OUT-RUN-DWV", codigo_dwv: "DWV-RUN-1", imovel_dwv: "Sim", status: "Venda", exibir_no_site_flag: true)

      result = described_class.new(tenant: current_tenant).send(:deactivate_removed_properties_by_ids, ["DWV-RUN-1"])

      expect(result).to eq(1)
      expect(current_habitation.reload).to have_attributes(status: "Suspenso", exibir_no_site_flag: false, last_sync_status: "inactive")
      expect(other_habitation.reload).to have_attributes(status: "Venda", exibir_no_site_flag: true, last_sync_status: nil)
    end
  end
end
