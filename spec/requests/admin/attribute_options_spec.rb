require "rails_helper"

RSpec.describe "Admin::AttributeOptions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "catalog-admin-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outro catalogo #{SecureRandom.hex(3)}", slug: "outro-catalogo-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista apenas atributos do tenant atual" do
    current_tenant_name = "Vista mar #{SecureRandom.hex(4)}"
    other_tenant_name = "Piscina externa #{SecureRandom.hex(4)}"
    admin.tenant.attribute_options.create!(context: "habitation", category: "feature", name: current_tenant_name)
    other_tenant.attribute_options.create!(context: "habitation", category: "feature", name: other_tenant_name)

    get admin_attribute_options_path, params: { query: current_tenant_name }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_tenant_name)
    expect(response.body).not_to include(other_tenant_name)
  end

  it "renderiza o estado vazio compacto e acessível dentro da tabela" do
    get admin_attribute_options_path, params: { query: "sem-resultado-#{SecureRandom.hex(8)}" }

    expect(response).to have_http_status(:ok)
    empty_state = Nokogiri::HTML(response.body).at_css("td .ax-empty-state.ax-empty-state--compact")
    expect(empty_state).to be_present
    expect(empty_state["role"]).to eq("status")
    expect(empty_state["aria-live"]).to eq("polite")
    expect(empty_state.at_css(".ax-empty-state__icon[aria-hidden='true']")).to be_present
  end

  it "cria atributo no tenant atual" do
    attribute_name = "Feira #{SecureRandom.hex(4)}"

    expect {
      post admin_attribute_options_path, params: {
        **csrf_params_from_response,
        attribute_option: {
          context: "lead",
          category: "source",
          name: attribute_name
        }
      }
    }.to change { admin.tenant.attribute_options.count }.by(1)

    expect(admin.tenant.attribute_options.find_by!(name: attribute_name)).to be_present
    expect(response).to redirect_to(admin_attribute_options_path)
  end

  it "limpa caches de filtros e formulários de imóveis ao criar e excluir característica" do
    form_cache_key = "admin/habitations/form_options/v2/tenant/#{admin.tenant_id}"
    filter_cache_key = "admin/habitations/filter_data/v8/tenant/#{admin.tenant_id}"
    attribute_name = "Característica cache #{SecureRandom.hex(4)}"

    Rails.cache.write(form_cache_key, { internal_features: ["cache antigo"] })
    Rails.cache.write(filter_cache_key, { amenities: ["cache antigo"] })

    post admin_attribute_options_path(format: :json), params: {
      **csrf_params_from_response,
      attribute_option: {
        context: "habitation",
        category: "feature",
        name: attribute_name
      }
    }, headers: json_headers

    expect(response).to have_http_status(:created)
    expect(Rails.cache.read(form_cache_key)).to be_nil
    expect(Rails.cache.read(filter_cache_key)).to be_nil

    option = admin.tenant.attribute_options.find_by!(name: attribute_name)
    Rails.cache.write(form_cache_key, { internal_features: [attribute_name] })
    Rails.cache.write(filter_cache_key, { amenities: [attribute_name] })

    delete admin_attribute_option_path(option, format: :json), params: csrf_params_from_response, headers: json_headers

    expect(response).to have_http_status(:no_content)
    expect(admin.tenant.attribute_options.where(id: option.id)).to be_empty
    expect(Rails.cache.read(form_cache_key)).to be_nil
    expect(Rails.cache.read(filter_cache_key)).to be_nil
  end

  it "permite ao dono da conta criar opção de cidade pelo modal" do
    post admin_attribute_options_path(format: :json), params: {
      **csrf_params_from_response,
      attribute_option: {
        context: "habitation",
        category: "city",
        name: "Camboriú"
      }
    }, headers: json_headers

    expect(response).to have_http_status(:created)
    expect(admin.tenant.attribute_options.find_by!(context: "habitation", category: "city", name: "Camboriú")).to be_present
  end

  it "lista no modal opções de endereço já usadas mesmo sem cadastro prévio no catálogo" do
    habitation = create(:habitation, tenant: admin.tenant, admin_user: admin)
    habitation.address.update!(bairro: "Alto Perequê")

    expect(admin.tenant.attribute_options.where(context: "habitation", category: "neighborhood", name: "Alto Perequê")).to be_empty

    get admin_attribute_options_path(format: :json),
        params: { context: "habitation", category: "neighborhood" },
        headers: json_headers

    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body).map { |option| option.fetch("name") }
    expect(names).to include("Alto Perequê")
    expect(admin.tenant.attribute_options.find_by!(context: "habitation", category: "neighborhood", name: "Alto Perequê")).to be_present
  end

  it "permite gerenciar bairro para perfil não dono com ação liberada no cadastro de imóvel" do
    locked_fields = Habitations::CadastroFieldRegistry.all_keys - ["acao:gerenciar_bairros"]
    manager_profile = admin.tenant.profiles.create!(
      name: "Gestor bairro #{SecureRandom.hex(3)}",
      axis: Profile::AXES[:vertical],
      position: 20,
      active: true,
      permissions: {
        "catalogos" => { "manage" => true },
        "imoveis" => { "view" => true, "edit" => true, "scope" => "all", "locked_fields" => locked_fields }
      }
    )
    manager = create(:admin_user, tenant: admin.tenant, profile: manager_profile, email: "catalog-neighborhood-manager-#{SecureRandom.hex(6)}@salute.test")
    sign_in manager
    @csrf_token = nil

    post admin_attribute_options_path(format: :json), params: {
      **csrf_params_from_response,
      attribute_option: {
        context: "habitation",
        category: "neighborhood",
        name: "Nova Praia"
      }
    }, headers: json_headers

    expect(response).to have_http_status(:created)
    expect(admin.tenant.attribute_options.find_by!(context: "habitation", category: "neighborhood", name: "Nova Praia")).to be_present
  end

  it "bloqueia opção de endereço para usuário que não é dono da conta" do
    manager_profile = admin.tenant.profiles.create!(
      name: "Gestor catálogo #{SecureRandom.hex(3)}",
      axis: Profile::AXES[:vertical],
      position: 20,
      active: true,
      permissions: { "catalogos" => { "manage" => true } }
    )
    manager = create(:admin_user, tenant: admin.tenant, profile: manager_profile, email: "catalog-manager-#{SecureRandom.hex(6)}@salute.test")
    sign_in manager
    @csrf_token = nil

    post admin_attribute_options_path(format: :json), params: {
      **csrf_params_from_response,
      attribute_option: {
        context: "habitation",
        category: "city",
        name: "Cidade bloqueada"
      }
    }, headers: json_headers

    expect(response).to have_http_status(:forbidden)
    expect(admin.tenant.attribute_options.where(category: "city", name: "Cidade bloqueada")).to be_empty
  end

  it "bloqueia gerenciamento de motivos de arquivamento para usuário que não é admin da conta" do
    manager_profile = admin.tenant.profiles.create!(
      name: "Gestor arquivamento #{SecureRandom.hex(3)}",
      axis: Profile::AXES[:vertical],
      position: 20,
      active: true,
      permissions: { "catalogos" => { "manage" => true } }
    )
    manager = create(:admin_user, tenant: admin.tenant, profile: manager_profile, email: "archive-reason-manager-#{SecureRandom.hex(6)}@salute.test")
    option = admin.tenant.attribute_options.create!(context: "lead", category: "archive_reason", name: "Sem fit")
    sign_in manager
    @csrf_token = nil

    get admin_attribute_options_path(format: :json), params: { context: "lead", category: "archive_reason" }, headers: json_headers
    expect(response).to have_http_status(:forbidden)

    post admin_attribute_options_path(format: :json), params: {
      **csrf_params_from_response,
      attribute_option: { context: "lead", category: "archive_reason", name: "Novo motivo" }
    }, headers: json_headers
    expect(response).to have_http_status(:forbidden)

    patch admin_attribute_option_path(option, format: :json), params: {
      **csrf_params_from_response,
      attribute_option: { context: "lead", category: "archive_reason", name: "Editado" }
    }, headers: json_headers
    expect(response).to have_http_status(:forbidden)

    delete admin_attribute_option_path(option, format: :json), params: csrf_params_from_response, headers: json_headers
    expect(response).to have_http_status(:forbidden)
    expect(option.reload.name).to eq("Sem fit")
  end

  def csrf_params_from_response
    token = csrf_token_from_catalog
    token.present? ? { authenticity_token: token } : {}
  end

  def csrf_token_from_catalog
    return @csrf_token if defined?(@csrf_token) && @csrf_token.present?

    get admin_attribute_options_path
    @csrf_token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content").to_s
  end

  def json_headers
    { "X-Requested-With" => "XMLHttpRequest", "X-CSRF-Token" => csrf_token_from_catalog.to_s }
  end
end
