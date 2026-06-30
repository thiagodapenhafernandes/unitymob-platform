require "rails_helper"

RSpec.describe Habitations::HierarchyAuditService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "audita parentes inválidos sem considerar empreendimentos de outro tenant" do
    current_tenant = Tenant.create!(name: "Conta A", slug: "conta-a")
    other_tenant = Tenant.create!(name: "Conta B", slug: "conta-b")
    Current.tenant = current_tenant

    create(
      :habitation,
      tenant: other_tenant,
      codigo: "DEV-010",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento Externo"
    )
    unit = create(
      :habitation,
      tenant: current_tenant,
      codigo: "UNIT-010",
      categoria: "Apartamento",
      tipo: "Unitário",
      nome_empreendimento: "Nome local",
      address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )
    unit.update_column(:codigo_empreendimento, "DEV-010")

    result = described_class.new.call

    expect(result[:metrics][:units_with_invalid_parent]).to eq(1)
    expect(result[:metrics][:units_name_diff_from_parent]).to eq(0)
  end

  it "compara unidade e empreendimento apenas dentro do mesmo tenant" do
    current_tenant = Tenant.create!(name: "Conta A", slug: "conta-a")
    other_tenant = Tenant.create!(name: "Conta B", slug: "conta-b")
    Current.tenant = current_tenant

    create(
      :habitation,
      tenant: current_tenant,
      codigo: "DEV-011",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento Local"
    )
    create(
      :habitation,
      tenant: other_tenant,
      codigo: "DEV-011",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento Externo"
    )
    unit = create(
      :habitation,
      tenant: current_tenant,
      codigo: "UNIT-011",
      categoria: "Apartamento",
      tipo: "Unitário",
      codigo_empreendimento: "DEV-011",
      nome_empreendimento: "Nome divergente",
      address_attributes: { logradouro: "Rua 200", numero: "20", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )
    unit.update_column(:nome_empreendimento, "Nome divergente")

    result = described_class.new.call

    expect(result[:metrics][:units_with_invalid_parent]).to eq(0)
    expect(result[:metrics][:units_name_diff_from_parent]).to eq(1)
  end
end
