require "rails_helper"

RSpec.describe Vista::DumpImportService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "não reaproveita proprietário existente em outro Tenant" do
    current_tenant = Tenant.create!(name: "Tenant dump #{SecureRandom.hex(3)}", slug: "tenant-dump-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro dump #{SecureRandom.hex(3)}", slug: "outro-dump-#{SecureRandom.hex(3)}")
    create(:proprietor, tenant: other_tenant, vista_code: "DUMP-PROP-1", name: "Proprietário Externo")

    Current.tenant = current_tenant
    service = described_class.new(dump_dir: Rails.root, dry_run: false)
    service.instance_variable_set(:@existing_proprietor_codes, Set["DUMP-PROP-1"])

    proprietor = service.send(:resolve_proprietor, "DUMP-PROP-1", described_class::Result.new)

    expect(proprietor).to be_nil
  end

  it "valida codigo DWV duplicado apenas dentro do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant dump dwv #{SecureRandom.hex(3)}", slug: "tenant-dump-dwv-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro dump dwv #{SecureRandom.hex(3)}", slug: "outro-dump-dwv-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: other_tenant, codigo: "OUT-DUMP-DWV", imovel_dwv: "Sim", codigo_dwv: "DUMP-DWV-1")

    Current.tenant = current_tenant
    service = described_class.new(dump_dir: Rails.root, dry_run: true)

    expect(service.send(:unique_dwv_code, "DUMP-DWV-1")).to eq("DUMP-DWV-1")
  end
end
