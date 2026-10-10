require "rails_helper"

RSpec.describe "Admin::HabitationDuplicates", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "duplicates-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  def own_scope_profile(name)
    Profile.create!(
      tenant: admin.tenant,
      name: "#{name} #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 9_200,
      permissions: { "imoveis" => { "view" => true, "scope" => "own" } }
    )
  end

  def create_matching_property(owner:, codigo:, **attrs)
    habitation = create(
      :habitation,
      tenant: admin.tenant,
      admin_user: owner,
      codigo: codigo,
      nome_empreendimento: "Edifício Aurora",
      bloco: "1203",
      status: "Venda",
      **attrs
    )
    habitation.create_address!(
      logradouro: "Rua 1500",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    habitation
  end

  def duplicate_query
    {
      street: "rua 1500",
      number: "100",
      building: "Edificio Aurora",
      unit: "apto 1203",
      status: "Venda"
    }
  end

  it "retorna apenas duplicatas do próprio corretor com escopo próprio" do
    profile = own_scope_profile("Corretor escopo próprio")
    broker = create(:admin_user, tenant: admin.tenant, profile:, email: "broker-dup-#{SecureRandom.hex(6)}@salute.test")
    peer = create(:admin_user, tenant: admin.tenant, email: "peer-dup-#{SecureRandom.hex(6)}@salute.test")
    own = create_matching_property(owner: broker, codigo: "DUP-PROPRIO-#{SecureRandom.hex(4)}")
    peer_property = create_matching_property(owner: peer, codigo: "DUP-ALHEIO-#{SecureRandom.hex(4)}")
    sign_in broker

    get check_admin_habitation_duplicate_path, params: duplicate_query

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("complete")).to eq(true)
    expect(payload.fetch("duplicate")).to eq(true)
    expect(payload.fetch("matches").map { |match| match["id"] }).to contain_exactly(own.id)
    expect(payload.fetch("matches").map { |match| match["codigo"] }).not_to include(peer_property.codigo)
  end

  it "nao expoe captacao ativa de outro corretor na checagem" do
    profile = own_scope_profile("Corretor captacao alheia")
    broker = create(:admin_user, tenant: admin.tenant, profile:, email: "broker-intake-#{SecureRandom.hex(6)}@salute.test")
    peer = create(:admin_user, tenant: admin.tenant, email: "peer-intake-#{SecureRandom.hex(6)}@salute.test")
    create_matching_property(
      owner: peer,
      codigo: "DUP-INTAKE-#{SecureRandom.hex(4)}",
      intake_origin: Habitation::INTAKE_ORIGIN_BROKER,
      intake_status: "submitted_for_admin_review",
      exibir_no_site_flag: false
    )
    sign_in broker

    get check_admin_habitation_duplicate_path, params: duplicate_query

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("complete")).to eq(true)
    expect(payload.fetch("duplicate")).to eq(false)
    expect(payload.fetch("matches")).to be_empty
  end

  it "mantem duplicata de imóvel com corretor designado no escopo" do
    profile = own_scope_profile("Corretor designado")
    broker = create(:admin_user, tenant: admin.tenant, profile:, email: "broker-designado-#{SecureRandom.hex(6)}@salute.test")
    peer = create(:admin_user, tenant: admin.tenant, email: "peer-designado-#{SecureRandom.hex(6)}@salute.test")
    assigned = create_matching_property(owner: peer, codigo: "DUP-DESIGNADO-#{SecureRandom.hex(4)}")
    HabitationBrokerAssignment.create!(habitation: assigned, admin_user: broker, role: "captador")
    sign_in broker

    get check_admin_habitation_duplicate_path, params: duplicate_query

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("duplicate")).to eq(true)
    expect(payload.fetch("matches").map { |match| match["id"] }).to include(assigned.id)
  end

  it "mantem todas as duplicatas para escopo total" do
    peer = create(:admin_user, tenant: admin.tenant, email: "peer-total-#{SecureRandom.hex(6)}@salute.test")
    own = create_matching_property(owner: admin, codigo: "DUP-TOTAL-1-#{SecureRandom.hex(4)}")
    other = create_matching_property(owner: peer, codigo: "DUP-TOTAL-2-#{SecureRandom.hex(4)}")

    get check_admin_habitation_duplicate_path, params: duplicate_query

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("duplicate")).to eq(true)
    expect(payload.fetch("matches").map { |match| match["id"] }).to include(own.id, other.id)
  end
end
