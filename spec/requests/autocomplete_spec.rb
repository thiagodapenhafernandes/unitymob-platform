require "rails_helper"

RSpec.describe "Autocomplete", type: :request do
  before { host! "localhost" }

  it "retorna sugestões apenas do tenant público padrão" do
    default_tenant = Tenant.default
    other_tenant = Tenant.create!(name: "Outro autocomplete #{SecureRandom.hex(3)}", slug: "outro-autocomplete-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: default_tenant).tap do |habitation|
      habitation.create_address!(logradouro: "Rua A", numero: "1", bairro: "Centro", cidade: "Cidade Atual", uf: "SC")
    end
    create(:habitation, tenant: other_tenant).tap do |habitation|
      habitation.create_address!(logradouro: "Rua B", numero: "2", bairro: "Bairro Externo", cidade: "Cidade Externa", uf: "SC")
    end

    get "/autocomplete/locations", params: { query: "Cidade" }

    expect(response).to have_http_status(:ok)
    labels = JSON.parse(response.body).map { |item| item.fetch("label") }
    expect(labels.join(" ")).to include("Cidade Atual")
    expect(labels.join(" ")).not_to include("Cidade Externa")
  end
end
