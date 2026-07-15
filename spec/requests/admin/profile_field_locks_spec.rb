require "rails_helper"

RSpec.describe "Admin::Profiles trava de campos do cadastro", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  def custom_profile
    Tenant.default.profiles.create!(
      name: "Custom #{SecureRandom.hex(4)}", axis: "vertical", position: 500 + SecureRandom.random_number(9000),
      permissions: { "imoveis" => { "view" => true, "media" => true, "manage" => false, "scope" => "own" } }
    )
  end

  it "renderiza o botão e o modal de campos do cadastro na edição do perfil" do
    sign_in create(:admin_user, :admin)
    profile = custom_profile

    get edit_admin_profile_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Campos do cadastro")
    expect(response.body).to include("Campos do cadastro de imóvel")
    expect(response.body).to include('name="profile[permissions][imoveis][locked_fields][]"')
    expect(response.body).to include('data-ax-modal-open="#imoveisFieldLocksModal"')
  end

  it "salva os campos marcados (travados) no perfil" do
    sign_in create(:admin_user, :admin)
    profile = custom_profile

    patch admin_profile_path(profile), params: {
      profile: { name: profile.name, active: "1", axis: "vertical", position: profile.position.to_s,
        permissions: { imoveis: { view: "1", scope: "own",
          locked_fields: ["", "tipo", "categoria", "publicar_lais_ai", "acao:gerar_ia", "chave_invalida_xyz"] } } }
    }

    locked = profile.reload.permissions.dig("imoveis", "locked_fields")
    expect(locked).to match_array(%w[tipo categoria publicar_lais_ai acao:gerar_ia])
    expect(locked).not_to include("chave_invalida_xyz")
  end

  it "salva lista vazia (tudo liberado) quando nada é marcado" do
    sign_in create(:admin_user, :admin)
    profile = custom_profile

    patch admin_profile_path(profile), params: {
      profile: { name: profile.name, active: "1", axis: "vertical", position: profile.position.to_s,
        permissions: { imoveis: { view: "1", scope: "own", locked_fields: [""] } } }
    }

    expect(profile.reload.permissions.dig("imoveis", "locked_fields")).to eq([])
  end
end
