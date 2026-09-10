require "rails_helper"

RSpec.describe "Salute: ações do cadastro", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    ActionController::Base.allow_forgery_protection = false
    sign_in admin
  end

  it "oferece publicação ou salvamento interno no cadastro direto" do
    get new_admin_habitation_path(habitation: { registration_profile: "apartamentos" })
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('button[name="publication_choice"]').map { |button| button['value'] }).to contain_exactly("publish", "internal")
  end

  %w[publish internal].each do |choice|
    it "salva cadastro direto com a escolha #{choice}" do
      post admin_habitations_path, params: {
        publication_choice: choice,
        habitation: { categoria: "Apartamento", registration_profile: "apartamentos", tipo: "Unitário", status: "Venda", nome_empreendimento: "Prédio #{SecureRandom.hex(4)}", bloco: "101", address_attributes: { logradouro: "Rua #{SecureRandom.hex(4)}", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" } }
      }
      expect(response).to have_http_status(:redirect)
      habitation = admin.tenant.habitations.order(:id).last
      expect(habitation.exibir_no_site_flag).to eq(choice == "publish")
    end
  end

  it "oferece a transferência de carteira ao desativar dentro do cadastro" do
    user = create(:admin_user, tenant: admin.tenant)
    get edit_admin_admin_user_path(user)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    toggle = doc.at_css('input[name="admin_user[active]"][type="checkbox"]')
    expect(toggle['data-action']).to include('admin-user-inactivation#prepareFromToggle')
    expect(doc.css('#inactivateUserModal form').size).to eq(1)
  end

  it "permite ao captador editar seu imóvel mesmo quando a atuação principal é diferente" do
    profile = admin.tenant.profiles.find_by!(key: "agent")
    profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    user = create(:admin_user, tenant: admin.tenant, profile: profile, acting_type: "sales")
    habitation = create(:habitation, tenant: admin.tenant, admin_user: user, status: "Aluguel")
    sign_in user
    get edit_admin_habitation_path(habitation)
    expect(response).to have_http_status(:ok), "#{response.location}: #{flash.to_h}"
  end
  it "não permite forçar publicação quando o perfil bloqueia essa opção" do
    profile = admin.tenant.profiles.find_by!(key: "agent")
    permissions = Profile.default_permissions_for("Corretor")
    permissions["imoveis"]["create"] = true
    permissions["imoveis"]["locked_fields"] = ["exibir_no_site_flag"]
    profile.update!(permissions: permissions)
    sign_in create(:admin_user, tenant: admin.tenant, profile: profile)
    expect {
      post admin_habitations_path, params: { publication_choice: "publish", habitation: { categoria: "Apartamento" } }
    }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "retira administradores sem captação do filtro e mantém os que têm imóvel" do
    with_capture = create(:admin_user, :admin, tenant: admin.tenant, name: "AdminComCaptacao")
    without_capture = create(:admin_user, :admin, tenant: admin.tenant, name: "AdminSemCaptacao")
    create(:habitation, tenant: admin.tenant, admin_user: with_capture)
    get filter_inspector_admin_habitations_path, headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    names = doc.css('select[name="corretor_id[]"] option, select[name="corretor_id"] option').map(&:text)
    expect(names).to include(with_capture.name)
    expect(names).not_to include(without_capture.name)
  end

  it "usa somente ativos por padrão e mantém a consulta explícita de todos" do
    property = create(:habitation, tenant: admin.tenant, status: "Vendido terceiros", valor_vendido_terceiros_cents: 850_000_00)
    get admin_habitations_path(q: property.codigo)
    expect(Nokogiri::HTML(response.body).css('.ax-property-card')).to be_empty
    get admin_habitations_path(q: property.codigo, status: "Todos")
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css('.ax-property-card').map(&:text).join).to include(property.codigo)
  end

  it "resolve a URL antiga pelo histórico antes de interpretar seu final como outro código" do
    other = create(:habitation, tenant: admin.tenant, codigo: "#{SecureRandom.random_number(10**9)}")
    property = create(:habitation, tenant: admin.tenant)
    old_slug = "apartamento-antigo-#{other.codigo}"
    property.update_column(:slug, old_slug)
    property.update!(titulo_anuncio: "Apartamento revisado")
    get habitation_path(old_slug, format: :json)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("codigo")).to eq(property.codigo)
  end

end
