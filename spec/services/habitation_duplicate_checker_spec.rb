require "rails_helper"

RSpec.describe HabitationDuplicateChecker do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "ignora imóveis do mesmo grupo de captação desdobrada sem ocultar imóveis comuns" do
    group_uuid = SecureRandom.uuid
    sale = create(:habitation, intake_group_uuid: group_uuid, nome_empreendimento: "Edifício Solar", bloco: "501")
    sale.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    rental = create(:habitation, intake_group_uuid: group_uuid, nome_empreendimento: "Edifício Solar", bloco: "501")
    rental.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    common_duplicate = create(:habitation, nome_empreendimento: "Edifício Solar", bloco: "501")
    common_duplicate.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: sale.logradouro,
      number: sale.numero,
      building: sale.nome_empreendimento,
      unit: sale.bloco,
      status: sale.status,
      ignored_id: sale.id
    ).call

    expect(result.matches).to include(common_duplicate)
    expect(result.matches).not_to include(rental)
  end

  it "bloqueia duplicidade somente quando o status comercial é igual" do
    sale = create(:habitation, status: "Venda", nome_empreendimento: "Edifício Solar", bloco: "501")
    sale.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")
    rental = create(:habitation, status: "Aluguel", nome_empreendimento: "Edifício Solar", bloco: "501")
    rental.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 1500",
      number: "10",
      building: "Edificio Solar",
      unit: "Apto 501",
      status: "Aluguel"
    ).call

    expect(result.matches).to include(rental)
    expect(result.matches).not_to include(sale)
  end

  it "não retorna imóveis duplicados de outro tenant" do
    current_tenant = Tenant.create!(name: "Conta A", slug: "conta-a")
    other_tenant = Tenant.create!(name: "Conta B", slug: "conta-b")
    Current.tenant = current_tenant

    local_duplicate = create(:habitation, tenant: current_tenant, status: "Venda", nome_empreendimento: "Edifício Solar", bloco: "501")
    local_duplicate.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    other_duplicate = create(:habitation, tenant: other_tenant, status: "Venda", nome_empreendimento: "Edifício Solar", bloco: "501")
    other_duplicate.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 1500",
      number: "10",
      building: "Edificio Solar",
      unit: "501",
      status: "Venda"
    ).call

    expect(result.matches).to include(local_duplicate)
    expect(result.matches).not_to include(other_duplicate)
  end

  it "não usa ignored_id de outro tenant para ignorar grupo local" do
    current_tenant = Tenant.create!(name: "Conta A", slug: "conta-a")
    other_tenant = Tenant.create!(name: "Conta B", slug: "conta-b")
    group_uuid = SecureRandom.uuid

    local_duplicate = create(:habitation, tenant: current_tenant, intake_group_uuid: group_uuid, nome_empreendimento: "Edifício Solar", bloco: "501")
    local_duplicate.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    ignored_from_other_tenant = create(:habitation, tenant: other_tenant, intake_group_uuid: group_uuid, nome_empreendimento: "Edifício Solar", bloco: "501")
    ignored_from_other_tenant.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 1500",
      number: "10",
      building: "Edificio Solar",
      unit: "501",
      status: "Venda",
      ignored_id: ignored_from_other_tenant.id,
      tenant: current_tenant
    ).call

    expect(result.matches).to include(local_duplicate)
    expect(result.matches).not_to include(ignored_from_other_tenant)
  end


  it "ignora imóveis inativos como duplicados" do
    inactive = create(:habitation, :unavailable, status: "Venda", nome_empreendimento: "Edifício Solar", bloco: "501")
    inactive.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 1500",
      number: "10",
      building: "Edifício Solar",
      unit: "501",
      status: "Venda"
    ).call

    expect(result.complete).to be(true)
    expect(result.matches).to be_empty
  end

  it "considera captação de corretor enviada para revisão como candidata de duplicidade" do
    intake = create(:habitation, :broker_intake, intake_status: "submitted_for_admin_review", status: "Venda", bloco: "501")
    intake.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 1500",
      number: "10",
      building: "Residencial Teste",
      unit: "501",
      status: "Venda"
    ).call

    expect(result.matches).to include(intake)
  end

  it "ignora rascunho de captação de corretor como candidato de duplicidade" do
    draft = create(:habitation, :broker_intake, intake_status: "draft", status: "Venda", bloco: "501")
    draft.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 1500",
      number: "10",
      building: "Residencial Teste",
      unit: "501",
      status: "Venda"
    ).call

    expect(result.matches).not_to include(draft)
  end

  it "normaliza tipo de logradouro ao comparar endereços" do
    existing = create(:habitation, status: "Venda", nome_empreendimento: "Edifício Solar", bloco: "501")
    existing.create_address!(logradouro: "Rua 1500", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "1500",
      number: "10",
      building: "Edificio Solar",
      unit: "501",
      status: "Venda"
    ).call

    expect(result.matches).to include(existing)
  end

  it "bloqueia imóvel sem unidade por rua e número quando status é igual" do
    house = create(:habitation, status: "Venda", nome_empreendimento: nil, bloco: nil, complemento: nil)
    house.create_address!(logradouro: "Rua 3000", numero: "50", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 3000",
      number: "50",
      building: "",
      unit: "",
      status: "Venda"
    ).call

    expect(result.matches).to include(house)
  end

  it "libera casa em condomínio no mesmo endereço quando complemento é diferente" do
    existing = create(:habitation, categoria: "Casa em Condomínio", status: "Venda", bloco: nil)
    existing.create_address!(
      logradouro: "Rua Higino João Pio",
      numero: "420",
      complemento: "01",
      bairro: "Praia do Estaleirinho",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    result = described_class.new(
      street: "Rua Higino Joao Pio",
      number: "420",
      building: "",
      unit: "",
      complement: "02",
      category: "Casa em Condomínio",
      status: "Venda",
      comparison: :condominium_unit
    ).call

    expect(result.complete).to be(true)
    expect(result.matches).to be_empty
  end

  it "bloqueia casa em condomínio no mesmo endereço quando complemento e bloco são iguais" do
    existing = create(:habitation, categoria: "Casa em Condomínio", status: "Venda", bloco: "A")
    existing.create_address!(
      logradouro: "Rua Higino João Pio",
      numero: "420",
      complemento: "01",
      bairro: "Praia do Estaleirinho",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    result = described_class.new(
      street: "Rua Higino Joao Pio",
      number: "420",
      building: "",
      unit: "Bloco A",
      complement: "01",
      category: "Casa em Condomínio",
      status: "Venda",
      comparison: :condominium_unit
    ).call

    expect(result.complete).to be(true)
    expect(result.matches).to include(existing)
  end

  it "não compara imóvel sem unidade com unidade do mesmo endereço" do
    apartment = create(:habitation, status: "Venda", nome_empreendimento: "Edifício Solar", bloco: "501")
    apartment.create_address!(logradouro: "Rua 3000", numero: "50", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 3000",
      number: "50",
      building: "",
      unit: "",
      status: "Venda"
    ).call

    expect(result.matches).not_to include(apartment)
  end

  it "não compara unidade de apartamento com cadastro do empreendimento sem unidade" do
    development = create(:habitation, status: "Venda", nome_empreendimento: "Edifício Solar", bloco: nil, complemento: nil)
    development.create_address!(logradouro: "Rua 3000", numero: "50", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC")

    result = described_class.new(
      street: "Rua 3000",
      number: "50",
      building: "Edifício Solar",
      unit: "501",
      status: "Venda",
      comparison: :unit
    ).call

    expect(result.complete).to be(true)
    expect(result.matches).not_to include(development)
  end

  it "não trata apartamentos diferentes da mesma torre como duplicados" do
    existing = create(:habitation, categoria: "Apartamento", status: "Venda", bloco: "B")
    existing.create_address!(
      logradouro: "Avenida Brasil",
      numero: "70",
      complemento: "801",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    result = described_class.new(
      street: "Avenida Brasil",
      number: "70",
      building: "Residencial Paris",
      unit: "B",
      complement: "401",
      category: "Apartamento",
      status: "Venda",
      comparison: :unit
    ).call

    expect(result.complete).to be(true)
    expect(result.matches).not_to include(existing)
  end

  it "bloqueia apartamento realmente duplicado na mesma torre e unidade" do
    existing = create(:habitation, categoria: "Apartamento", status: "Venda", bloco: "B")
    existing.create_address!(
      logradouro: "Avenida Brasil",
      numero: "70",
      complemento: "801",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    result = described_class.new(
      street: "Avenida Brasil",
      number: "70",
      building: "Residencial Paris",
      unit: "B",
      complement: "801",
      category: "Apartamento",
      status: "Venda",
      comparison: :unit
    ).call

    expect(result.complete).to be(true)
    expect(result.matches).to include(existing)
  end
end
