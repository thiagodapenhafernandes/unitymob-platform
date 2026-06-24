require "rails_helper"

RSpec.describe "Admin context items", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe atalhos de contexto da sessao depois que o usuario entra em um item especifico" do
    habitation = create(:habitation, codigo: "CTXPIN-#{SecureRandom.hex(4)}")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("ax-context-pins")
    expect(response.body).not_to include("Imóvel #{habitation.codigo}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-context-pins")
    expect(response.body).to include("Imóvel #{habitation.codigo}")
    expect(session[:admin_context_items]).to include(
      a_hash_including(
        "key" => "habitation:#{habitation.id}",
        "admin_user_id" => admin.id
      )
    )

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-context-pins")
    expect(response.body).to include("Imóvel #{habitation.codigo}")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-context-pins")
    expect(response.body).to include("Imóvel #{habitation.codigo}")
  end

  it "mantem somente itens realmente navegados pelo usuario na sessao" do
    first_habitation = create(:habitation, codigo: "CTXOLD-#{SecureRandom.hex(4)}")
    current_habitation = create(:habitation, codigo: "CTXNOW-#{SecureRandom.hex(4)}")

    get edit_admin_habitation_path(first_habitation)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Imóvel #{first_habitation.codigo}")

    get edit_admin_habitation_path(current_habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-context-pins")
    expect(response.body).to include("Imóvel #{current_habitation.codigo}")
    expect(response.body).to include("Imóvel #{first_habitation.codigo}")
  end

  it "usa permissoes do usuario logado para exibir contexto de proprietario" do
    sign_out admin
    profile = Profile.create!(
      name: "Contexto proprietario #{SecureRandom.hex(4)}",
      permissions: {
        "dashboard" => { "view" => true },
        "proprietarios" => { "view" => true, "manage" => true }
      }
    )
    user = create(:admin_user, role: :editor, profile: profile)
    proprietor = create(:proprietor, name: "Proprietário contexto #{SecureRandom.hex(4)}")

    sign_in user
    get edit_admin_proprietor_path(proprietor)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-context-pins")
    expect(response.body).to include(proprietor.name)
  end
end
