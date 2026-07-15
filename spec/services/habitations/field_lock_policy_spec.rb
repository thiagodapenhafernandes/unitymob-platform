require "rails_helper"

RSpec.describe Habitations::FieldLockPolicy do
  let(:tenant) { Tenant.default }

  def profile_with(imoveis_perms)
    tenant.profiles.create!(name: "P#{SecureRandom.hex(4)}", axis: "vertical",
                            permissions: { "imoveis" => imoveis_perms })
  end

  def user_with(profile)
    create(:admin_user, email: "flp-#{SecureRandom.hex(4)}@salute.test").tap do |u|
      u.update!(profile: profile)
    end
  end

  it "dono da conta edita tudo (nada travado)" do
    owner = create(:admin_user, :admin, email: "owner-#{SecureRandom.hex(4)}@salute.test")
    policy = described_class.for(owner)
    expect(policy.unrestricted?).to be(true)
    expect(policy.locked_keys).to be_empty
  end

  it "sem config, cai no default do card #1 (trava tipo/portais/IA, libera status/imediacoes)" do
    user = user_with(profile_with("view" => true, "scope" => "own"))
    policy = described_class.for(user)

    expect(policy.field_locked?("tipo")).to be(true)
    expect(policy.field_locked?("publicar_lais_ai")).to be(true)
    expect(policy.field_locked?("acao:gerar_ia")).to be(true)
    expect(policy.field_locked?("status")).to be(false)
    expect(policy.allowed_top_level_params).to include("status", "valor_venda_formatted")
    expect(policy.allowed_top_level_params).not_to include("tipo", "categoria", "publicar_lais_ai")
    expect(policy.allowed_address_subkeys).to eq(["imediacoes"])
  end

  it "respeita locked_fields configurado no perfil" do
    # trava 'status' (normalmente livre) e libera 'tipo' (normalmente travado)
    user = user_with(profile_with("view" => true, "scope" => "own", "locked_fields" => ["status"]))
    policy = described_class.for(user)

    expect(policy.field_locked?("status")).to be(true)
    expect(policy.field_locked?("tipo")).to be(false)
    expect(policy.allowed_top_level_params).to include("tipo")
    expect(policy.allowed_top_level_params).not_to include("status")
  end
end
