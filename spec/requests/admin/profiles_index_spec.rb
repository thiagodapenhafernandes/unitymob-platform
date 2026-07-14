require "rails_helper"

RSpec.describe "Admin::Profiles index", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "profiles-index-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outra hierarquia #{SecureRandom.hex(3)}", slug: "outra-hierarquia-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista a hierarquia apenas do tenant atual" do
    current_name = "Gestão local #{SecureRandom.hex(4)}"
    other_name = "Gestão externa #{SecureRandom.hex(4)}"
    Profile.create!(tenant: admin.tenant, name: current_name, axis: "vertical", position: 650, permissions: {})
    Profile.create!(tenant: other_tenant, name: other_name, axis: "vertical", position: 650, permissions: {})

    get admin_profiles_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_name, "Perfis de acesso", "Hierarquia e funções")
    expect(response.body).not_to include(other_name)
    expect(response.body).to include(new_admin_profile_path(axis: "vertical"), new_admin_profile_path(axis: "horizontal"))
    expect(response.body).to include("Perfis verticais e horizontais da conta atual", "ax-btn--icon")
    expect(Nokogiri::HTML(response.body).css("thead th[scope='col']").size).to eq(7)
  end

  it "renderiza o detalhe tenant-scoped no cabecalho e tabela compartilhados" do
    profile = Profile.create!(tenant: admin.tenant, name: "Gestão #{SecureRandom.hex(4)}", axis: "vertical", position: 650, permissions: {})

    get admin_profile_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", profile.name, "ax-operational-panel", "ax-table__col--w-220")
    expect(response.body).to include("Resumo estrutural do perfil", 'scope="row"')
  end

  it "renderiza a matriz com caption, cabecalhos e escopos nomeados" do
    get new_admin_profile_path(axis: "vertical")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    matrix = html.at_css("table.prof-matrix")
    expect(matrix.at_css("caption").text).to include("Permissões por recurso")
    expect(matrix.css("thead th[scope='col']").size).to eq(8)
    expect(matrix.css("tbody th[scope='row']").size).to eq(Profile::RESOURCES.size)
    expect(matrix.css("select[aria-label^='Escopo de ']").size).to eq(Profile::RESOURCES.count { |resource| resource[:scopeable] })
  end
end
