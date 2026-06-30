require "rails_helper"

RSpec.describe Habitations::ProprietorLinker do
  let(:tenant) { Tenant.create!(name: "Tenant proprietario #{SecureRandom.hex(3)}", slug: "tenant-proprietario-#{SecureRandom.hex(3)}") }
  let(:other_tenant) { Tenant.create!(name: "Outro proprietario #{SecureRandom.hex(3)}", slug: "outro-proprietario-#{SecureRandom.hex(3)}") }

  it "não vincula proprietário de outro tenant pelo mesmo telefone" do
    other_proprietor = create(:proprietor, tenant: other_tenant, name: "Proprietário Externo", mobile_phone: "(47) 99999-0000")
    habitation = create(
      :habitation,
      tenant: tenant,
      proprietario: "Proprietário Atual",
      proprietario_celular: "(47) 99999-0000",
      proprietario_email: "atual@example.com"
    )

    described_class.new(habitation).call

    expect(habitation.proprietor).to be_present
    expect(habitation.proprietor.tenant).to eq(tenant)
    expect(habitation.proprietor).not_to eq(other_proprietor)
  end

  it "ignora proprietário selecionado de outro tenant" do
    other_proprietor = create(:proprietor, tenant: other_tenant, name: "Proprietário Externo")
    habitation = create(
      :habitation,
      tenant: tenant,
      proprietor_id: other_proprietor.id,
      proprietario: "Proprietário Novo",
      proprietario_email: "novo@example.com"
    )

    described_class.new(habitation).call

    expect(habitation.proprietor).to be_present
    expect(habitation.proprietor.tenant).to eq(tenant)
    expect(habitation.proprietor).not_to eq(other_proprietor)
  end

  it "sincroniza cidade do proprietário nas observações de captação" do
    proprietor = create(:proprietor, tenant: tenant, name: "Proprietário Local", city: "Itajaí")
    habitation = create(
      :habitation,
      tenant: tenant,
      proprietor: proprietor,
      proprietario: "Proprietário Local",
      observacoes_visitas: "Dias/horários para visita: Segunda"
    )

    described_class.new(habitation).call

    expect(habitation.proprietario_cidade).to eq("Itajaí")
    expect(habitation.observacoes_visitas).to include("Dias/horários para visita: Segunda")
    expect(habitation.observacoes_visitas).to include("Cidade do proprietário: Itajaí")
  end
end
