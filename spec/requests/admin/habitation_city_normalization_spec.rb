require "rails_helper"

RSpec.describe "Cidades do catálogo por conta", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:spellings) { ["Balneário Camboriú", "Balneario Camboriu", "balneario camboriu"] }
  let!(:properties) do
    spellings.each_with_index.map do |city, index|
      create(:habitation, tenant: admin.tenant, codigo: "CITY-#{index}",
        titulo_anuncio: "Imóvel preservado #{index}", cidade: city).tap do |property|
        property.address.update!(cidade: city)
      end
    end
  end

  before do
    host! "localhost"
    sign_in admin
    Rails.cache.clear
  end

  it "mostra uma opção e preserva a seleção de URLs antigas" do
    other_tenant = Tenant.create!(name: "Conta de fora do filtro", slug: "other-options-#{SecureRandom.hex(4)}")
    foreign_property = create(:habitation, tenant: other_tenant, cidade: "Florianópolis")
    foreign_property.address.update!(cidade: "Florianópolis")

    get filter_inspector_admin_habitations_path(cidade: spellings),
      headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)
    options = Nokogiri::HTML(response.body).css('select[name="cidade[]"] option').reject { |option| option["value"].blank? }
    expect(options.size).to eq(1)
    expect(Habitation.normalize_location_value(options.first.text)).to eq("balneario camboriu")
    expect(options.first["selected"]).to be_present
    expect(properties.map { |property| property.reload.address.cidade }).to eq(spellings)
  end

  it "encontra todas as grafias, preserva os registros e respeita a conta" do
    other_tenant = Tenant.create!(name: "Outra conta cidades", slug: "other-city-#{SecureRandom.hex(4)}")
    foreign_property = create(:habitation, tenant: other_tenant, titulo_anuncio: "Imóvel de outra conta", cidade: spellings.first)
    outside = create(:habitation, tenant: admin.tenant, titulo_anuncio: "Imóvel em outra cidade", cidade: "Joinville")
    outside.address.update!(cidade: "Joinville")
    before_values = properties.map { |property| [property.attributes, property.address.attributes] }

    get admin_habitations_path(cidade: ["BALNEARIO CAMBORIU"])

    expect(response).to have_http_status(:ok)
    properties.each { |property| expect(response.body).to include(property.titulo_anuncio) }
    expect(response.body).not_to include(foreign_property.titulo_anuncio, outside.titulo_anuncio)
    expect(properties.map { |property| [property.reload.attributes, property.address.reload.attributes] }).to eq(before_values)
  end
end
