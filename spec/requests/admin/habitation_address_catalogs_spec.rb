require "rails_helper"

RSpec.describe "Admin::Habitations catálogos de endereço", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "renderiza gerenciadores de endereço para o dono da conta" do
    admin = create(:admin_user, :admin, email: "address-catalog-owner-#{SecureRandom.hex(6)}@salute.test")
    habitation = create(:habitation, tenant: admin.tenant, admin_user: admin)

    sign_in admin
    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)

    expect(document.at_css('[data-attribute-manager-category-value="street_type"][data-select-id="habitation_address_attributes_tipo_endereco"]')).to be_present
    expect(document.at_css('[data-attribute-manager-category-value="neighborhood"][data-select-id="habitation_address_attributes_bairro"]')).to be_present
    expect(document.at_css('[data-attribute-manager-category-value="commercial_neighborhood"][data-select-id="habitation_address_attributes_bairro_comercial"]')).to be_present
    expect(document.at_css('[data-attribute-manager-category-value="city"][data-select-id="habitation_address_attributes_cidade"]')).to be_present
    expect(document.at_css('[data-attribute-manager-category-value="imediacoes"][data-select-id="address-imediacoes-tags"]')).to be_present
  end

  it "renderiza gerenciador de bairro para perfil com ação liberada" do
    owner = create(:admin_user, :admin, email: "address-catalog-owner-#{SecureRandom.hex(6)}@salute.test")
    profile = owner.tenant.profiles.create!(
      name: "Gestor bairros #{SecureRandom.hex(3)}",
      axis: Profile::AXES[:vertical],
      position: 20,
      active: true,
      permissions: {
        "catalogos" => { "manage" => true },
        "imoveis" => {
          "view" => true,
          "edit" => true,
          "scope" => "all",
          "locked_fields" => Habitations::CadastroFieldRegistry.all_keys - ["acao:gerenciar_bairros"]
        }
      }
    )
    manager = create(:admin_user, tenant: owner.tenant, profile: profile, email: "address-catalog-manager-#{SecureRandom.hex(6)}@salute.test")
    habitation = create(:habitation, tenant: owner.tenant, admin_user: owner)

    sign_in manager
    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)

    expect(document.at_css('[data-attribute-manager-category-value="neighborhood"][data-field-lock-action="acao:gerenciar_bairros"]')).to be_present
    expect(document.at_css('[data-attribute-manager-category-value="city"][data-field-lock-action="acao:gerenciar_cidades"]')).to be_nil
  end
end
