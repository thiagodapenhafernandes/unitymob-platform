require "rails_helper"

RSpec.describe "Escopo de consulta dos dados internos do imóvel", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.default }
  let(:profile) { tenant.profiles.create!(name: "Consulta interna #{SecureRandom.hex(4)}", axis: "vertical", position: 7321, permissions: Profile.default_permissions_for("Gerente").deep_merge("imoveis" => { "internal_data_scope" => "all" })) }
  let(:user) { create(:admin_user, tenant: tenant, profile: profile, acting_type: :sales) }
  let(:other_broker) { create(:admin_user, tenant: tenant) }
  let(:habitation) { create(:habitation, tenant: tenant, admin_user: other_broker, status: "Aluguel", proprietario: "Contato interno reservado", proprietario_celular: "47988880000", captador_commission_percentage: 7.25) }

  before do
    host! "localhost"
    ActionController::Base.allow_forgery_protection = false
    habitation.fichas_cadastro.attach(io: StringIO.new("ficha"), filename: "ficha-reservada.pdf", content_type: "application/pdf")
    sign_in user
  end

  it "libera contatos e fichas de outro corretor sem liberar edição nem comissões" do
    get admin_habitation_path(habitation)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contato interno reservado", "ficha-reservada.pdf")
    expect(response.body).not_to include("Comissão captador (%)")
    get edit_admin_habitation_path(habitation)
    expect(response).to redirect_to(admin_habitations_path)
  end

  %w[own team].each do |scope|
    it "oculta contatos e fichas fora do escopo #{scope}" do
      profile.update!(permissions: profile.permissions.deep_merge("imoveis" => { "internal_data_scope" => scope }))
      get admin_habitation_path(habitation)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Contato interno reservado", "ficha-reservada.pdf")
    end
  end

  it "respeita o escopo de consulta também no formulário mesmo quando há edição global" do
    user.update!(acting_type: :both)
    profile.update!(permissions: profile.permissions.deep_merge("imoveis" => { "scope" => "all", "internal_data_scope" => "own" }))
    get edit_admin_habitation_path(habitation)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Contato interno reservado", "ficha-reservada.pdf")
    expect(response.body).to include("Seu perfil não permite consultar os documentos internos")
  end

  it "persiste a escolha no editor e permite voltar à regra atual" do
    sign_out user
    sign_in create(:admin_user, :admin, tenant: tenant)
    get edit_admin_profile_path(profile)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    select = document.at_css('select[name="profile[permissions][imoveis][internal_data_scope]"]')
    expect(select.css("option").map { |option| option["value"] }).to eq(["", "own", "team", "all"])
    expect(select.at_css("option[selected]")["value"]).to eq("all")

    %w[own team all invalid].each do |scope|
      patch admin_profile_path(profile), params: { profile: { name: profile.name, axis: profile.axis, position: profile.position, permissions: { imoveis: { view: "1", scope: "team", internal_data_scope: scope } } } }
      expect(response).to have_http_status(:redirect)
      expect(profile.reload.habitation_internal_data_scope).to eq(scope == "invalid" ? "own" : scope)
    end
    patch admin_profile_path(profile), params: { profile: { name: profile.name, axis: profile.axis, position: profile.position, permissions: { imoveis: { view: "1", internal_data_scope: "" } } } }
    expect(profile.reload.habitation_internal_data_scope).to be_nil
  end

  it "não permite acesso a imóvel de outra conta mesmo com Todos" do
    foreign_tenant = Tenant.create!(name: "Outra conta", slug: "outra-#{SecureRandom.hex(4)}")
    foreign = create(:habitation, tenant: foreign_tenant, proprietario: "Proprietário externo")
    get admin_habitation_path(foreign)
    expect(response).to have_http_status(:not_found)
  end
end
