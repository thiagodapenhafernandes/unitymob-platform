require "rails_helper"

# Fase 1 da granularidade: `delete` é ação PRÓPRIA, separada de `manage`.
# O que precisa ficar provado aqui:
#   1. manage NÃO implica delete (o caso "gerencia mas não exclui");
#   2. leads#destroy exige permissão (antes bastava enxergar o lead);
#   3. delete NÃO ignora o escopo — quem tem "próprios" não apaga o alheio.
RSpec.describe "Admin delete permission", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.create!(name: "Tenant delete #{SecureRandom.hex(3)}", slug: "tenant-delete-#{SecureRandom.hex(3)}") }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before { host! "localhost" }

  # Perfil vertical isolado por exemplo: evita vazar estado entre os casos.
  def build_profile(permissions, position: 700)
    Profile.create!(
      tenant: tenant,
      name: "Perfil #{SecureRandom.hex(6)}",
      axis: Profile::AXES[:vertical],
      position: position,
      permissions: permissions
    )
  end

  # Perfil que cria/edita tudo: isola o efeito do switch de excluir.
  def imoveis_permissions(delete:, scope:)
    {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => true, "edit" => true, "delete" => delete, "scope" => scope }
    }
  end

  def leads_permissions(delete:, scope: "all")
    {
      "admin" => false,
      "dashboard" => { "view" => true },
      "leads" => { "view" => true, "edit" => true, "delete" => delete, "scope" => scope }
    }
  end

  def csrf_params_from_response
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content")
    token.present? ? { authenticity_token: token } : {}
  end

  def delete_habitation(habitation)
    get admin_habitations_path
    delete admin_habitation_path(habitation), params: csrf_params_from_response
  end

  def delete_lead(lead)
    get admin_leads_path
    delete admin_lead_path(lead), params: csrf_params_from_response
  end

  describe "Imóveis" do
    it "não exclui quando o perfil gerencia mas não tem delete" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(delete: false, scope: "all")))
      habitation = create(:habitation, admin_user: user)
      sign_in user

      delete_habitation(habitation)

      expect(response).to redirect_to(admin_habitations_path)
      expect(Habitation.exists?(habitation.id)).to be(true)
    end

    it "exclui quando o perfil tem delete com escopo total" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(delete: true, scope: "all")))
      habitation = create(:habitation, admin_user: user)
      sign_in user

      delete_habitation(habitation)

      expect(Habitation.exists?(habitation.id)).to be(false)
    end

    it "exclui o próprio imóvel quando tem delete com escopo 'próprios'" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(delete: true, scope: "own")))
      habitation = create(:habitation, admin_user: user)
      sign_in user

      delete_habitation(habitation)

      expect(Habitation.exists?(habitation.id)).to be(false)
    end

    # Regressão: set_habitation resolve só por tenant. Sem o recorte por
    # registro, delete + escopo "próprios" apagaria imóvel de qualquer um.
    it "não exclui imóvel alheio quando o escopo é 'próprios'" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(delete: true, scope: "own")))
      other = create(:admin_user, profile: build_profile(imoveis_permissions(delete: false, scope: "own"), position: 701))
      habitation = create(:habitation, admin_user: other)
      sign_in user

      delete_habitation(habitation)

      expect(response).to redirect_to(admin_habitations_path)
      expect(Habitation.exists?(habitation.id)).to be(true)
    end
  end

  describe "Leads" do
    # Antes desta fase, leads#destroy só exigia :view + escopo do registro.
    it "não exclui quando o perfil gerencia mas não tem delete" do
      user = create(:admin_user, profile: build_profile(leads_permissions(delete: false)))
      lead = create(:lead, admin_user: user)
      sign_in user

      delete_lead(lead)

      expect(response).to redirect_to(admin_leads_path)
      expect(Lead.exists?(lead.id)).to be(true)
    end

    it "exclui quando o perfil tem delete" do
      user = create(:admin_user, profile: build_profile(leads_permissions(delete: true)))
      lead = create(:lead, admin_user: user)
      sign_in user

      delete_lead(lead)

      expect(Lead.exists?(lead.id)).to be(false)
    end
  end

  # A matriz de /admin/profiles é montada a partir de Profile::RESOURCES, então a
  # coluna nova precisa aparecer e persistir sem código de tela dedicado.
  describe "Tela de perfis" do
    let(:admin) { create(:admin_user, :admin, email: "delete-perm-#{SecureRandom.hex(6)}@salute.test") }

    before { sign_in admin }

    it "renderiza a coluna Excluir na matriz de permissões" do
      get new_admin_profile_path(axis: "vertical")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Excluir")
    end

    it "persiste o switch de excluir vindo do formulário" do
      profile = build_profile(imoveis_permissions(delete: false, scope: "all"), position: 742)

      get edit_admin_profile_path(profile)
      patch admin_profile_path(profile), params: csrf_params_from_response.merge(
        profile: {
          name: profile.name,
          axis: Profile::AXES[:vertical],
          active: "1",
          position: profile.position,
          permissions: {
            imoveis: { view: "1", media: "1", manage: "1", delete: "1", scope: "all" }
          }
        }
      )

      expect(profile.reload.can?(:delete, :imoveis)).to be(true)
    end
  end

  describe "Vocabulário" do
    it "expõe delete como ação configurável de imóveis e leads" do
      %w[imoveis leads].each do |key|
        resource = Profile::RESOURCES.find { |res| res[:key] == key }
        expect(resource[:actions]).to include("delete")
      end

      expect(Profile::ACTION_LABELS["delete"]).to eq("Excluir")
    end

    it "não concede delete por herança de manage" do
      profile = build_profile(imoveis_permissions(delete: false, scope: "all"))

      expect(profile.can?(:edit, :imoveis)).to be(true)
      expect(profile.can?(:delete, :imoveis)).to be(false)
    end

    it "mantém o Administrador excluindo (admin curto-circuita o JSON)" do
      profile = build_profile({ "admin" => true })

      expect(profile.can?(:delete, :imoveis)).to be(true)
      expect(profile.can?(:delete, :leads)).to be(true)
    end
  end
end
