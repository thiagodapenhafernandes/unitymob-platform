require "rails_helper"

RSpec.describe "Admin habitation filter inspector", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o inspector em um turbo frame separado" do
    create(:habitation, bairro: "Centro")

    get filter_inspector_admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('turbo-frame id="admin_habitations_filter_inspector"')
    expect(response.body).to include("Filtros do catálogo")
    expect(response.body).to include('autocomplete="off"')
    expect(response.body).to include('data-turbo-frame="_top"')
    expect(response.body).to include('name="codigo"')
    expect(response.body).to include('name="q"')
    expect(response.body).to include('name="logradouro"')
    expect(response.body.scan('autocomplete="off"').size).to be >= 8
    expect(response.body).to include('name="bairro[]"')
    expect(response.body).to include('multiple="multiple"')
    expect(response.body).to include('filter-multi-wrap')
    expect(response.body).to include('data-controller="tom-select"')
    expect(response.body).to include("Centro")
  end

  it "mantém o inspector pesado fora da primeira resposta da listagem" do
    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin_habitations_filter_inspector"')
    expect(response.body).to include("habitations-inspector-skeleton")
    expect(response.body).not_to include('<form class="habitations-inspector__form"')
  end
end
