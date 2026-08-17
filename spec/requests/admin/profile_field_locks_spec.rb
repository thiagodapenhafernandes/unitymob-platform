require "rails_helper"

RSpec.describe "Admin::Profiles trava de campos do cadastro", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    host! "localhost"
    allow_any_instance_of(Admin::ProfilesController).to receive(:verified_request?).and_return(true)
    allow_any_instance_of(Admin::HabitationsController).to receive(:verified_request?).and_return(true)
  end

  def custom_profile
    Tenant.default.profiles.create!(
      name: "Custom #{SecureRandom.hex(4)}", axis: "vertical", position: 500 + SecureRandom.random_number(9000),
      permissions: { "imoveis" => { "view" => true, "media" => true, "manage" => false, "scope" => "own" } }
    )
  end

  def tenant_owner_profile_id(profile)
    profile.tenant.profiles.vertical.find_by!(key: "tenant_owner").id
  end

  def csrf_params_from_response
    token =
      Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')&.[]("value") ||
      Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content")
    token.present? ? { authenticity_token: token } : {}
  end

  it "renderiza o botão e o modal de campos do cadastro na edição do perfil" do
    profile = custom_profile
    sign_in create(:admin_user, :admin, tenant: profile.tenant)

    get edit_admin_profile_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Campos do cadastro")
    expect(response.body).to include("Campos do cadastro de imóvel")
    expect(response.body).to include('name="profile[permissions][imoveis][locked_fields][]"')
    expect(response.body).to include('data-ax-modal-open="#imoveisFieldLocksModal"')
    expect(response.body).to include("Identificação e sinalizadores")
    %w[Site Destaque Lançamento Placa Exclusivo].each do |label|
      expect(response.body).to include(label)
    end
    expect(response.body).to include("Super destaque", "Imóvel DWV")
  end

  it "mantém todos os controles renderizados do imóvel representados no modal" do
    profile = custom_profile
    sign_in create(:admin_user, :admin, tenant: profile.tenant)

    get new_admin_habitation_path, params: {
      habitation: {
        registration_profile: "apartamentos",
        categoria: "Apartamento",
        status: "Venda"
      }
    }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    rendered_paths = document.css("form[action='/admin/habitations'] [name^='habitation[']").filter_map do |control|
      name = control["name"].to_s
      segments = name.scan(/\[([^\]]+)\]/).flatten.reject { |segment| segment.match?(/\A(?:\d+|NEW_RECORD)\z/) }
      next if segments.empty?

      segments.first == "address_attributes" ? segments.first(2).join(".") : segments.first
    end.uniq

    registered_paths = Habitations::CadastroFieldRegistry.all_items.flat_map do |item|
      [(item[:param_path] || item[:key] unless item[:kind] == :action), *item[:extra_params]]
    end
    allowed_structural = Habitations::CadastroFieldRegistry::NON_LOCKABLE_FORM_FIELDS

    expect(rendered_paths - registered_paths - allowed_structural).to be_empty

    rendered_sections = document.css(".ax-form-section__title").map { |title| title.text.squish }.uniq
    registered_sections = Habitations::CadastroFieldRegistry.groups.map { |group| group[:section] }
    expect(rendered_sections - registered_sections - ["Identificação"]).to be_empty
  end

  it "expõe ao formulário somente campos e ações liberados pelo modal" do
    profile = custom_profile
    permissions = profile.permissions.deep_dup
    permissions["imoveis"]["manage"] = true
    permissions["imoveis"]["locked_fields"] = ["titulo_anuncio", "logradouro", "acao:gerenciar_responsaveis"]
    profile.update!(permissions: permissions)
    user = create(:admin_user, tenant: profile.tenant, profile: profile)
    habitation = create(:habitation, tenant: profile.tenant, admin_user: user)
    sign_in user

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    root = Nokogiri::HTML(response.body).at_css(".habitation-form-ui[data-controller*='broker-field-policy']")
    allowed_fields = JSON.parse(root["data-broker-field-policy-allowed-fields-value"])
    allowed_actions = JSON.parse(root["data-broker-field-policy-allowed-actions-value"])
    expect(allowed_fields).not_to include("titulo_anuncio", "address_attributes.logradouro", "broker_assignments_attributes")
    expect(allowed_fields).to include("status", "address_attributes.cidade")
    expect(allowed_actions).not_to include("acao:gerenciar_responsaveis")
  end

  it "expõe ao formulário as travas da função horizontal efetiva do usuário" do
    tenant = Tenant.default
    vertical = tenant.profiles.create!(
      name: "Gestor vertical #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 700 + SecureRandom.random_number(2000),
      permissions: {
        "imoveis" => { "view" => true, "edit" => true, "scope" => "team", "locked_fields" => ["nome_empreendimento"] }
      }
    )
    horizontal = tenant.profiles.create!(
      name: "Administrativo horizontal #{SecureRandom.hex(4)}",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: {
        "imoveis" => { "view" => true, "edit" => true, "scope" => "all", "locked_fields" => ["status"] }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: vertical, horizontal_profile: horizontal)
    habitation = create(:habitation, tenant: tenant, admin_user: user)
    sign_in user

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    root = Nokogiri::HTML(response.body).at_css(".habitation-form-ui[data-controller*='broker-field-policy']")
    allowed_fields = JSON.parse(root["data-broker-field-policy-allowed-fields-value"])
    expect(allowed_fields).to include("nome_empreendimento")
    expect(allowed_fields).not_to include("status")
  end

  it "aplica a política de travas também no formulário de cadastro novo" do
    profile = custom_profile
    permissions = profile.permissions.deep_dup
    permissions["imoveis"]["create"] = true
    permissions["imoveis"]["edit"] = true
    permissions["imoveis"]["locked_fields"] = ["status"]
    profile.update!(permissions: permissions)
    sign_in create(:admin_user, tenant: profile.tenant, profile: profile)

    get new_admin_habitation_path, params: {
      habitation: {
        registration_profile: "apartamentos",
        categoria: "Apartamento",
        status: "Venda"
      }
    }

    expect(response).to have_http_status(:ok)
    root = Nokogiri::HTML(response.body).at_css(".habitation-form-ui[data-controller*='broker-field-policy']")
    expect(root).to be_present
    allowed_fields = JSON.parse(root["data-broker-field-policy-allowed-fields-value"])
    expect(allowed_fields).not_to include("status")
  end

  it "descarta no update os valores travados mesmo se a requisição for manipulada" do
    profile = custom_profile
    permissions = profile.permissions.deep_dup
    permissions["imoveis"]["edit"] = true
    permissions["imoveis"]["locked_fields"] = ["titulo_anuncio", "logradouro"]
    profile.update!(permissions: permissions)
    user = create(:admin_user, tenant: profile.tenant, profile: profile)
    habitation = create(:habitation, tenant: profile.tenant, admin_user: user, titulo_anuncio: "Título original", status: "Venda")
    habitation.create_address!(logradouro: "Rua original", bairro: "Centro", cidade: "Cidade original", uf: "SC")
    sign_in user

    get edit_admin_habitation_path(habitation)

    patch admin_habitation_path(habitation), params: {
      **csrf_params_from_response,
      habitation: {
        titulo_anuncio: "Título indevido",
        status: "Aluguel",
        address_attributes: {
          id: habitation.address.id,
          logradouro: "Rua indevida",
          cidade: "Cidade permitida"
        }
      }
    }

    expect(response).to have_http_status(:redirect)
    expect(habitation.reload).to have_attributes(titulo_anuncio: "Título original", status: "Aluguel")
    expect(habitation.address.reload).to have_attributes(logradouro: "Rua original", cidade: "Cidade permitida")
  end

  it "salva os campos marcados (travados) no perfil" do
    profile = custom_profile
    sign_in create(:admin_user, :admin, tenant: profile.tenant)

    get edit_admin_profile_path(profile)

    patch admin_profile_path(profile), params: {
      **csrf_params_from_response,
      profile: { name: profile.name, active: "1", axis: "vertical", insert_after_profile_id: tenant_owner_profile_id(profile),
        permissions: { imoveis: { view: "1", scope: "own",
          locked_fields: ["", "tipo", "categoria", "publicar_lais_ai", "acao:gerar_ia", "chave_invalida_xyz"] } } }
    }

    expect(response).to redirect_to(edit_admin_profile_path(profile))
    locked = profile.reload.permissions.dig("imoveis", "locked_fields")
    expect(locked).to match_array(%w[tipo categoria publicar_lais_ai acao:gerar_ia])
    expect(locked).not_to include("chave_invalida_xyz")
  end

  it "salva lista vazia (tudo liberado) quando nada é marcado" do
    profile = custom_profile
    sign_in create(:admin_user, :admin, tenant: profile.tenant)

    get edit_admin_profile_path(profile)

    patch admin_profile_path(profile), params: {
      **csrf_params_from_response,
      profile: { name: profile.name, active: "1", axis: "vertical", insert_after_profile_id: tenant_owner_profile_id(profile),
        permissions: { imoveis: { view: "1", scope: "own", locked_fields: [""] } } }
    }

    expect(profile.reload.permissions.dig("imoveis", "locked_fields")).to eq([])
  end
end
