require "rails_helper"

RSpec.describe "Admin::Proprietors", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "lista proprietários filtrados sem expor registros de outro tenant" do
    admin = create(:admin_user, :admin)
    sign_in admin
    create(:proprietor, tenant: admin.tenant, name: "Proprietário Visível", city: "Itajaí")
    create(:proprietor, tenant: admin.tenant, name: "Proprietário Fora do Filtro", city: "Blumenau")
    other_tenant = Tenant.create!(name: "Outro tenant proprietário", slug: "outro-proprietario-#{SecureRandom.hex(4)}")
    create(:proprietor, tenant: other_tenant, name: "Proprietário Outro Tenant", city: "Itajaí")

    get admin_proprietors_path, params: { filters: { name: "Visível", city: "Itajaí" } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Proprietário Visível")
    expect(response.body).not_to include("Proprietário Fora do Filtro")
    expect(response.body).not_to include("Proprietário Outro Tenant")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('label[for="filters_name"]')).to be_present
    expect(html.at_css('label[for="filters_phone"]')).to be_present
    expect(html.at_css('label[for="filters_email"]')).to be_present
    expect(html.at_css('label[for="filters_city"]')).to be_present
    expect(html.at_css('label[for="filters_vista_code"]')).to be_nil
    expect(html.at_css('label[for="filters_cpf_cnpj"]')).to be_nil
    expect(html.at_css('a[aria-label="Editar proprietário Proprietário Visível"] i[aria-hidden="true"]')).to be_present
  end

  it "filtra proprietários por telefone e email sem usar filtros administrativos removidos" do
    admin = create(:admin_user, :admin)
    sign_in admin
    matching = create(:proprietor, tenant: admin.tenant, name: "Proprietário Telefone", email: "telefone@example.com", phone_primary: "(47) 99999-0000", cpf_cnpj: "12345678901")
    create(:proprietor, tenant: admin.tenant, name: "Proprietário Outro", email: "outro@example.com", phone_primary: "(47) 98888-0000", cpf_cnpj: "98765432100")

    get admin_proprietors_path, params: { filters: { phone: "(47) 99999-0000", email: "telefone", cpf_cnpj: "98765432100" } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.name)
    expect(response.body).not_to include("Proprietário Outro")
  end

  it "renderiza o editor com imóveis filtrados apenas do proprietário e tenant atuais" do
    admin = create(:admin_user, :admin)
    sign_in admin
    proprietor = create(:proprietor, tenant: admin.tenant, name: "Proprietário do editor")
    other_proprietor = create(:proprietor, tenant: admin.tenant, name: "Outro proprietário")
    visible_habitation = create(:habitation, tenant: admin.tenant, proprietor:, codigo: "PROP-VISIVEL", status: "Venda")
    create(:habitation, tenant: admin.tenant, proprietor:, codigo: "PROP-OUTRO-STATUS", status: "Locação")
    create(:habitation, tenant: admin.tenant, proprietor: other_proprietor, codigo: "PROP-OUTRO-DONO", status: "Venda")

    get edit_admin_proprietor_path(proprietor), params: { habitation_q: visible_habitation.codigo, habitation_status: "Venda" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Editar proprietário", "Imóveis vinculados", "PROP-VISIVEL")
    expect(response.body).not_to include("PROP-OUTRO-STATUS", "PROP-OUTRO-DONO")
  end

  it "renderiza o cadastro com todos os grupos e contratos de comportamento" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get new_admin_proprietor_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Novo proprietário", "Dados do proprietário", "Endereço", "Dados do cônjuge")
    expect(response.body).to include('data-controller="cep-search"', 'data-controller="phone-input"', 'data-controller="tom-select"')
    expect(response.body).to include('name="proprietor[name]"', 'name="proprietor[profile_image]"', 'name="proprietor[notes]"')
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('input[type="email"][name="proprietor[email]"]')).to be_present
    expect(html.at_css('input[type="tel"][name="proprietor[phone_primary]"][data-controller="phone-input"]')).to be_present
    expect(html.at_css('select[name="proprietor[marital_status]"][data-controller="tom-select"]')).to be_present
    expect(html.at_css('input[name="proprietor[cep]"][data-cep-search-target="cep"]')).to be_present
    expect(html.at_css('textarea[name="proprietor[notes]"]')).to be_present
  end

  it "cria proprietário rápido e retorna payload para selecionar no cadastro do imóvel" do
    admin = create(:admin_user, :admin)
    sign_in admin

    expect {
      post quick_create_admin_proprietors_path,
           params: {
             proprietor: {
               name: "Proprietário Modal",
               phone_primary: "(47) 99999-1111",
               email: "modal@example.com",
               city: "Itajaí"
             }
           },
           headers: { "ACCEPT" => "application/json" }
    }.to change(Proprietor, :count).by(1)

    expect(response).to have_http_status(:created)
    payload = JSON.parse(response.body)
    proprietor = Proprietor.last
    expect(payload).to include("id" => proprietor.id)
    expect(payload["name"]).to include("Proprietário Modal")
    expect(proprietor).to have_attributes(
      role: "owner",
      phone_primary: "5547999991111",
      email: "modal@example.com",
      city: "Itajaí"
    )
  end

  it "busca e edita proprietário rápido somente para administrador/administrativo" do
    admin = create(:admin_user, :admin)
    sign_in admin
    proprietor = create(:proprietor, tenant: admin.tenant, name: "Dono Busca", phone_primary: "(47) 98888-7777", city: "Itapema")

    get quick_search_admin_proprietors_path,
        params: { q: "8888" },
        headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload.fetch("proprietors").first).to include(
      "id" => proprietor.id,
      "name" => "Dono Busca",
      "city" => "Itapema"
    )

    patch quick_update_admin_proprietor_path(proprietor),
          params: { proprietor: { name: "Dono Atualizado", phone_primary: "(47) 97777-6666", email: "dono@example.com", city: "Camboriú" } },
          headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(proprietor.reload).to have_attributes(
      name: "Dono Atualizado",
      phone_primary: "5547977776666",
      email: "dono@example.com",
      city: "Camboriú"
    )
  end

  it "bloqueia busca rápida para usuário sem gerenciar captações" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(
        permissions: Profile.default_permissions_for("Corretor").merge(
          "captacoes" => { "view" => true, "manage" => false },
          "proprietarios" => { "view" => true, "manage" => false }
        )
      )
    end
    broker = create(:admin_user, profile: broker_profile)
    sign_in broker

    get quick_search_admin_proprietors_path,
        params: { q: "Dono" },
        headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:forbidden)
  end

  it "permite criação rápida para perfil Administrativo" do
    internal_management_profile = Tenant.default.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME)
    administrative_profile = Tenant.default.profiles.find_by!(key: "administrativo")
    internal_management_profile.update!(
      permissions: Profile.default_permissions_for("Administrativo").merge(
        "proprietarios" => { "view" => true, "manage" => true }
      )
    )
    administrative_profile.update!(
      permissions: Profile.default_permissions_for("Administrativo").merge(
        "proprietarios" => { "view" => true, "manage" => true }
      )
    )
    administrative = create(:admin_user, profile: internal_management_profile, horizontal_profile: administrative_profile)
    sign_in administrative

    post quick_create_admin_proprietors_path,
         params: { proprietor: { name: "Proprietário Administrativo" } },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["errors"]).to include("Telefone é obrigatório.", "Cidade é obrigatória.")

    post quick_create_admin_proprietors_path,
         params: { proprietor: { name: "Proprietário Administrativo", phone_primary: "(47) 98888-0001", city: "Camboriú" } },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["name"]).to eq("Proprietário Administrativo")
  end

  it "não duplica proprietário rápido quando o telefone já existe" do
    admin = create(:admin_user, :admin)
    sign_in admin
    existing = create(:proprietor, tenant: admin.tenant, name: "Dono Existente", phone_primary: "(47) 99999-2222", city: "Itajaí")

    expect {
      post quick_create_admin_proprietors_path,
           params: {
             proprietor: {
               name: "Outro Nome",
               phone_primary: "55 (47) 99999-2222",
               email: "novo@example.com",
               city: "Camboriú"
             }
           },
           headers: { "ACCEPT" => "application/json" }
    }.not_to change(Proprietor, :count)

    expect(response).to have_http_status(:created)
    payload = JSON.parse(response.body)
    expect(payload).to include("id" => existing.id, "name" => "Dono Existente", "city" => "Itajaí")
    expect(existing.reload).to have_attributes(name: "Dono Existente", city: "Itajaí")
  end

  it "permite busca e criação rápida para corretor com captações sem liberar CRUD de proprietários" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
    broker = create(:admin_user, profile: broker_profile)
    sign_in broker
    create(:proprietor, tenant: broker.tenant, name: "Proprietário Captação", phone_primary: "(47) 97777-1111", city: "Itajaí")

    get quick_search_admin_proprietors_path,
        params: { q: "97777" },
        headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("proprietors").first["name"]).to eq("Proprietário Captação")

    expect {
      post quick_create_admin_proprietors_path,
           params: { proprietor: { name: "Novo Captado", phone_primary: "(47) 96666-2222", city: "Itapema" } },
           headers: { "ACCEPT" => "application/json" }
    }.to change(Proprietor, :count).by(1)

    get admin_proprietors_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "permite corretor atualizar campos preenchidos no fluxo rápido da captação e bloqueia telefone duplicado" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
    broker = create(:admin_user, profile: broker_profile)
    sign_in broker
    proprietor = create(
      :proprietor,
      tenant: broker.tenant,
      name: "Dono Antigo",
      phone_primary: "(47) 97777-1111",
      email: "antigo@example.com",
      city: "Itajaí"
    )
    duplicate = create(:proprietor, tenant: broker.tenant, name: "Dono Duplicado", phone_primary: "(47) 96666-2222", city: "Camboriú")

    patch quick_update_admin_proprietor_path(proprietor),
          params: {
            proprietor: {
              name: "Dono Atualizado",
              phone_primary: "(47) 95555-3333",
              email: "",
              city: "Porto Belo"
            }
          },
          headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(proprietor.reload).to have_attributes(
      name: "Dono Atualizado",
      phone_primary: "5547955553333",
      email: "",
      city: "Porto Belo"
    )

    patch quick_update_admin_proprietor_path(proprietor),
          params: { proprietor: { name: "Outro Nome", phone_primary: "(47) 96666-2222", city: "Itapema" } },
          headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["errors"]).to include("Telefone já vinculado ao proprietário #{duplicate.name}.")
    expect(proprietor.reload.phone_primary).to eq("5547955553333")
  end
end
