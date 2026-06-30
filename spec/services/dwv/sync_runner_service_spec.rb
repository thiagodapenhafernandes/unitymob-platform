require "rails_helper"

RSpec.describe Dwv::SyncRunnerService do
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
