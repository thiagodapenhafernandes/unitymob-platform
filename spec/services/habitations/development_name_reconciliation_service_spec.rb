require "rails_helper"

RSpec.describe Habitations::DevelopmentNameReconciliationService do
  let(:tenant) { Tenant.default }
  let(:code) { "REC-#{SecureRandom.hex(6)}" }
  let(:other_code) { "REC-#{SecureRandom.hex(6)}" }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "preenche nome de empreendimento somente quando nome e código estão vazios" do
    habitation = create(:habitation, tenant: tenant, codigo: code, nome_empreendimento: nil, codigo_empreendimento: nil)

    service = described_class.new(tenant: tenant, mappings: { code => "Lá Belle Verte" }, dry_run: false).call

    expect(service.stats[:updated]).to eq(1)
    expect(habitation.reload.nome_empreendimento).to eq("Lá Belle Verte")
    expect(habitation.codigo_empreendimento).to be_blank
  end

  it "não altera imóvel que já possui nome de empreendimento" do
    habitation = create(:habitation, tenant: tenant, codigo: code, nome_empreendimento: "Nome Existente", codigo_empreendimento: nil)

    service = described_class.new(tenant: tenant, mappings: { code => "Lá Belle Verte" }, dry_run: false).call

    expect(service.stats[:skipped_existing_development]).to eq(1)
    expect(habitation.reload.nome_empreendimento).to eq("Nome Existente")
  end

  it "não altera imóvel que já possui código de empreendimento" do
    development = create(:habitation, tenant: tenant, codigo: other_code, tipo: "Empreendimento", nome_empreendimento: "Empreendimento Existente")
    habitation = create(:habitation, tenant: tenant, codigo: code, nome_empreendimento: nil, codigo_empreendimento: development.codigo)

    service = described_class.new(tenant: tenant, mappings: { code => "Torremolinos" }, dry_run: false).call

    expect(service.stats[:skipped_existing_development]).to eq(1)
    expect(habitation.reload.nome_empreendimento).to eq("Empreendimento Existente")
    expect(habitation.codigo_empreendimento).to eq(development.codigo)
  end

  it "registra audit log como sistema" do
    habitation = create(:habitation, tenant: tenant, codigo: code, nome_empreendimento: nil, codigo_empreendimento: nil)

    expect do
      described_class.new(tenant: tenant, mappings: { code => "Lá Belle Verte" }, dry_run: false).call
    end.to change(HabitationAuditLog.where(habitation: habitation), :count).by(1)

    log = HabitationAuditLog.where(habitation: habitation).last
    expect(log.source).to eq("sistema")
    expect(log.action).to eq("bulk_updated")
    expect(log.changed_fields).to eq(["nome_empreendimento"])
    expect(log.changeset).to eq(
      "nome_empreendimento" => {
        "before" => nil,
        "after" => "Lá Belle Verte"
      }
    )
  end

  it "em dry-run apenas reporta o que seria alterado" do
    habitation = create(:habitation, tenant: tenant, codigo: code, nome_empreendimento: nil, codigo_empreendimento: nil)

    service = described_class.new(tenant: tenant, mappings: { code => "Lá Belle Verte" }, dry_run: true).call

    expect(service.stats[:would_update]).to eq(1)
    expect(habitation.reload.nome_empreendimento).to be_blank
  end
end
