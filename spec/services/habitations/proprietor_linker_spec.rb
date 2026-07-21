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

  it "preserva o proprietário selecionado mesmo quando campos legados divergem" do
    selected_proprietor = create(
      :proprietor,
      tenant: tenant,
      name: "Embraed Empreendimentos",
      vista_code: "14",
      email: nil,
      phone_primary: nil,
      mobile_phone: nil,
      business_phone: nil,
      residential_phone: nil
    )
    create(
      :proprietor,
      tenant: tenant,
      name: "Marcelo",
      vista_code: "24518",
      email: nil,
      phone_primary: nil,
      mobile_phone: nil,
      business_phone: nil,
      residential_phone: nil
    )
    habitation = create(
      :habitation,
      tenant: tenant,
      proprietor: selected_proprietor,
      proprietario: "Marcelo",
      proprietario_codigo: "24518",
      proprietario_email: nil,
      proprietario_celular: "(47) 99289-8305"
    )

    described_class.new(habitation).call

    expect(selected_proprietor.reload.name).to eq("Embraed Empreendimentos")
    expect(habitation.proprietor).to eq(selected_proprietor)
    expect(habitation.proprietario).to eq("Embraed Empreendimentos")
    expect(habitation.proprietario_codigo).to eq("14")
    expect(habitation.proprietario_email).to be_nil
    expect(habitation.proprietario_celular).to be_nil
  end

  it "respeita uma troca manual nova de proprietário no formulário" do
    old_proprietor = create(:proprietor, tenant: tenant, name: "Embraed Empreendimentos", vista_code: "14")
    new_proprietor = create(:proprietor, tenant: tenant, name: "Marcelo", vista_code: "24518")
    habitation = create(
      :habitation,
      tenant: tenant,
      proprietor: old_proprietor,
      proprietario: "Embraed Empreendimentos",
      proprietario_codigo: "14"
    )
    habitation.proprietor = new_proprietor

    described_class.new(habitation).call

    expect(habitation.proprietor).to eq(new_proprietor)
    expect(habitation.proprietario).to eq("Marcelo")
    expect(habitation.proprietario_codigo).to eq("24518")
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
