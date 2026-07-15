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

  it "separa ações liberadas dos campos de formulário" do
    user = user_with(profile_with("view" => true, "scope" => "own", "locked_fields" => ["acao:gerar_ia", "status"]))
    policy = described_class.for(user)

    expect(policy.allowed_action_keys).to include("acao:buscar_cep", "acao:gerenciar_responsaveis")
    expect(policy.allowed_action_keys).not_to include("acao:gerar_ia")
    expect(policy.allowed_frontend_fields).not_to include("acao:buscar_cep")
  end

  it "mapeia corretamente CEP e tipo de logradouro como endereço aninhado e bloco como campo do imóvel" do
    user = user_with(profile_with("view" => true, "scope" => "own", "locked_fields" => []))
    policy = described_class.for(user)

    expect(policy.allowed_address_subkeys).to include("cep", "tipo_endereco")
    expect(policy.allowed_top_level_params).to include("bloco")
    expect(policy.allowed_top_level_params).not_to include("cep", "tipo_endereco")
  end

  it "aplica cada trava do modal às listas usadas pelo formulário e pelo servidor" do
    profile = profile_with("view" => true, "scope" => "own", "locked_fields" => [])
    user = user_with(profile)

    Habitations::CadastroFieldRegistry.all_items.each do |item|
      permissions = profile.permissions.deep_dup
      permissions["imoveis"]["locked_fields"] = [item[:key]]
      profile.update_columns(permissions: permissions)
      policy = described_class.for(user.reload)

      if item[:kind] == :action
        expect(policy.allowed_action_keys).not_to include(item[:key]), "ação não travada: #{item[:key]}"
      else
        path = item[:param_path] || item[:key]
        expect(policy.allowed_frontend_fields).not_to include(path), "controle não travado no formulário: #{item[:key]}"

        if path.start_with?("address_attributes.")
          expect(policy.allowed_address_subkeys).not_to include(path.split(".").last), "endereço aceito pelo servidor: #{item[:key]}"
        else
          expect(policy.allowed_top_level_params).not_to include(path), "campo aceito pelo servidor: #{item[:key]}"
        end
      end

      Array(item[:extra_params]).each do |extra_param|
        expect(policy.allowed_top_level_params).not_to include(extra_param), "parâmetro auxiliar aceito: #{item[:key]} / #{extra_param}"
        expect(policy.allowed_frontend_fields).not_to include(extra_param), "controle auxiliar liberado: #{item[:key]} / #{extra_param}"
      end
    end
  end
end
