require "rails_helper"

RSpec.describe Habitations::HierarchyNormalizerService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "sincroniza unidades somente com empreendimentos do mesmo tenant" do
    current_tenant = Tenant.create!(name: "Conta A", slug: "conta-a")
    other_tenant = Tenant.create!(name: "Conta B", slug: "conta-b")
    Current.tenant = current_tenant

    local_development = create(
      :habitation,
      tenant: current_tenant,
      codigo: "DEV-001",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento Local"
    )
    other_development = create(
      :habitation,
      tenant: other_tenant,
      codigo: "DEV-001",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento Externo"
    )
    unit = create(
      :habitation,
      tenant: current_tenant,
      codigo: "UNIT-001",
      categoria: "Apartamento",
      tipo: "Unitário",
      codigo_empreendimento: local_development.codigo,
      nome_empreendimento: "Nome antigo",
      address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )

    described_class.new.call

    expect(unit.reload.nome_empreendimento).to eq("Empreendimento Local")
    expect(other_development.reload.nome_empreendimento).to eq("Empreendimento Externo")
  end

  it "não usa empreendimento de outro tenant como pai quando o tenant local não possui o código" do
    current_tenant = Tenant.create!(name: "Conta A", slug: "conta-a")
    other_tenant = Tenant.create!(name: "Conta B", slug: "conta-b")
    Current.tenant = current_tenant

    create(
      :habitation,
      tenant: other_tenant,
      codigo: "DEV-002",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento Externo"
    )
    unit = create(
      :habitation,
      tenant: current_tenant,
      codigo: "UNIT-002",
      categoria: "Apartamento",
      tipo: "Unitário",
      nome_empreendimento: "Nome local",
      address_attributes: { logradouro: "Rua 200", numero: "20", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )
    unit.update_column(:codigo_empreendimento, "DEV-002")

    described_class.new.call

    expect(unit.reload.nome_empreendimento).to eq("Nome local")
  end
end
