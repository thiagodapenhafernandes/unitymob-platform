# frozen_string_literal: true

require "rails_helper"

RSpec.describe Habitations::VistaPayloadDevelopmentNameBackfillService do
  let(:tenant) do
    Tenant.create!(
      name: "Tenant payload empreendimento #{SecureRandom.hex(3)}",
      slug: "tenant-payload-empreendimento-#{SecureRandom.hex(3)}"
    )
  end

  it "preenche nome do empreendimento a partir do vista_payload salvo" do
    habitation = create(
      :habitation,
      tenant: tenant,
      codigo: "8581",
      imovel_dwv: "Nao",
      categoria: "Apartamento",
      tipo: "Unitário",
      nome_empreendimento: nil,
      vista_payload: { "Empreendimento" => "Tropical Summer" }
    )

    result = described_class.new(tenant: tenant, apply: true).call

    expect(result.candidates).to eq(1)
    expect(result.updated).to eq(1)
    expect(habitation.reload.nome_empreendimento).to eq("Tropical Summer")
  end

  it "não preenche casas isoladas sem vínculo de empreendimento" do
    habitation = create(
      :habitation,
      tenant: tenant,
      codigo: "9054",
      imovel_dwv: "Nao",
      categoria: "Casa",
      tipo: "Unitário",
      nome_empreendimento: nil,
      vista_payload: { "Empreendimento" => "Nome indevido" }
    )

    result = described_class.new(tenant: tenant, apply: true).call

    expect(result.updated).to eq(0)
    expect(result.skipped).to eq(1)
    expect(habitation.reload.nome_empreendimento).to be_nil
  end

  it "respeita tenant e modo diagnóstico" do
    other_tenant = Tenant.create!(
      name: "Outro payload empreendimento #{SecureRandom.hex(3)}",
      slug: "outro-payload-empreendimento-#{SecureRandom.hex(3)}"
    )
    current = create(
      :habitation,
      tenant: tenant,
      codigo: "8582",
      imovel_dwv: "Nao",
      categoria: "Cobertura",
      tipo: "Unitário",
      nome_empreendimento: nil,
      vista_payload: { "Empreendimento" => "Residencial Atual" }
    )
    create(
      :habitation,
      tenant: other_tenant,
      codigo: "8582",
      imovel_dwv: "Nao",
      categoria: "Cobertura",
      tipo: "Unitário",
      nome_empreendimento: nil,
      vista_payload: { "Empreendimento" => "Residencial Outro" }
    )

    result = described_class.new(tenant: tenant).call

    expect(result.candidates).to eq(1)
    expect(result.updated).to eq(0)
    expect(result.samples).to include(hash_including(codigo: "8582", after: "Residencial Atual"))
    expect(current.reload.nome_empreendimento).to be_nil
  end
end
