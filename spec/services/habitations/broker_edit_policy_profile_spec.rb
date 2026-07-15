require "rails_helper"

RSpec.describe Habitations::BrokerEditPolicy, "por perfil (Fase 4)", type: :model do
  let(:habitation) { build(:habitation, proprietario_email: nil, proprietario_cidade: nil) }

  def user_with(imoveis_perms)
    profile = Tenant.default.profiles.create!(
      name: "P#{SecureRandom.hex(4)}", axis: "vertical", position: 500 + SecureRandom.random_number(9000),
      permissions: { "imoveis" => { "view" => true, "scope" => "own" }.merge(imoveis_perms) }
    )
    create(:admin_user, email: "bpp-#{SecureRandom.hex(4)}@salute.test").tap { |u| u.update!(profile: profile) }
  end

  def filtered_keys(user, params)
    described_class.filter(params.stringify_keys, habitation: habitation, admin_user: user).keys
  end

  let(:sample) { { "tipo" => "x", "status" => "x", "meta_title" => "x", "valor_venda_formatted" => "x" } }

  it "dono da conta edita tudo" do
    owner = create(:admin_user, :admin, email: "own-#{SecureRandom.hex(4)}@salute.test")
    expect(filtered_keys(owner, sample)).to match_array(sample.keys)
  end

  it "full-access (locked_fields: []) edita tudo" do
    gestor = user_with("scope" => "all", "manage" => true, "locked_fields" => [])
    expect(filtered_keys(gestor, sample)).to match_array(sample.keys)
  end

  it "corretor com travas do card #1 é restrito (tipo/meta_title fora, status/valor dentro)" do
    corretor = user_with("locked_fields" => Habitations::FieldLockPolicy.default_locked_keys.to_a)
    keys = filtered_keys(corretor, sample)
    expect(keys).to include("status", "valor_venda_formatted")
    expect(keys).not_to include("tipo", "meta_title")
  end

  it "respeita trava específica configurada (trava status, libera tipo)" do
    custom = user_with("scope" => "all", "locked_fields" => ["status"])
    keys = filtered_keys(custom, sample)
    expect(keys).to include("tipo", "meta_title")
    expect(keys).not_to include("status")
  end

  it "descarta no servidor campo simples, endereço e ação composta travados" do
    custom = user_with(
      "scope" => "all",
      "locked_fields" => ["titulo_anuncio", "logradouro", "acao:gerenciar_responsaveis"]
    )
    params = {
      "titulo_anuncio" => "Tentativa bloqueada",
      "status" => "Venda",
      "broker_assignments_attributes" => { "0" => { "admin_user_id" => "123", "role" => "captador" } },
      "address_attributes" => { "logradouro" => "Rua bloqueada", "cidade" => "Cidade liberada" }
    }

    filtered = described_class.filter(params, habitation: habitation, admin_user: custom)

    expect(filtered).to include("status")
    expect(filtered).not_to have_key("titulo_anuncio")
    expect(filtered).not_to have_key("broker_assignments_attributes")
    expect(filtered.dig("address_attributes", "cidade")).to eq("Cidade liberada")
    expect(filtered.dig("address_attributes", "logradouro")).to be_nil
  end
end
