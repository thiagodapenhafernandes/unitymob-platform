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

    get new_admin_habitation_path

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

  it "descarta no update os valores travados mesmo se a requisição for manipulada" do
    profile = custom_profile
    permissions = profile.permissions.deep_dup
    permissions["imoveis"]["manage"] = true
    permissions["imoveis"]["locked_fields"] = ["titulo_anuncio", "logradouro"]
    profile.update!(permissions: permissions)
    user = create(:admin_user, tenant: profile.tenant, profile: profile)
    habitation = create(:habitation, tenant: profile.tenant, admin_user: user, titulo_anuncio: "Título original", status: "Venda")
    habitation.create_address!(logradouro: "Rua original", bairro: "Centro", cidade: "Cidade original", uf: "SC")
    sign_in user

    patch admin_habitation_path(habitation), params: {
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

    patch admin_profile_path(profile), params: {
      profile: { name: profile.name, active: "1", axis: "vertical", position: profile.position.to_s,
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

    patch admin_profile_path(profile), params: {
      profile: { name: profile.name, active: "1", axis: "vertical", position: profile.position.to_s,
        permissions: { imoveis: { view: "1", scope: "own", locked_fields: [""] } } }
    }

    expect(profile.reload.permissions.dig("imoveis", "locked_fields")).to eq([])
  end
end
