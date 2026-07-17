require "rails_helper"

# Fase 2 da granularidade: `manage` (criar + editar) desmembrado em `create` e
# `edit` para Imóveis e Leads. O que precisa ficar provado:
#   1. criar e editar são independentes (um não concede o outro);
#   2. leads#update exige :edit (antes bastava enxergar o lead);
#   3. Leads não tem `create` — o admin não cadastra lead.
RSpec.describe "Admin create/edit permission", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.create!(name: "Tenant create edit #{SecureRandom.hex(3)}", slug: "tenant-create-edit-#{SecureRandom.hex(3)}") }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before { host! "localhost" }

  def build_profile(permissions, position: 760)
    Profile.create!(
      tenant: tenant,
      name: "Perfil #{SecureRandom.hex(6)}",
      axis: Profile::AXES[:vertical],
      position: position,
      permissions: permissions
    )
  end

  def imoveis_permissions(create:, edit:, scope: "all")
    {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => create, "edit" => edit, "delete" => false, "scope" => scope }
    }
  end

  def csrf_params_from_response
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content")
    token.present? ? { authenticity_token: token } : {}
  end

  def patch_lead(lead, params)
    get admin_lead_path(lead)
    patch admin_lead_path(lead), params: csrf_params_from_response.merge(params)
  end

  describe "Imóveis · criar" do
    it "bloqueia novo imóvel quando o perfil só edita" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(create: false, edit: true)))
      sign_in user

      get new_admin_habitation_path

      expect(response).not_to have_http_status(:ok)
    end

    it "permite novo imóvel quando o perfil cria" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(create: true, edit: false)))
      sign_in user

      get new_admin_habitation_path

      expect(response).to have_http_status(:ok)
    end

    it "não deixa criar de fato quem só edita" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(create: false, edit: true)))
      sign_in user

      expect {
        get new_admin_habitation_path
        post admin_habitations_path, params: csrf_params_from_response.merge(habitation: { codigo: "NEW-#{SecureRandom.hex(4)}", categoria: "Casa em Condomínio" })
      }.not_to change(Habitation, :count)
    end
  end

  describe "Imóveis · editar" do
    # can_edit_habitation? = can?(:edit) || é dono do imóvel. Por isso o imóvel
    # do teste é de OUTRO usuário: isola o efeito do switch.
    it "bloqueia edição de imóvel alheio quando o perfil só cria" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(create: true, edit: false)))
      owner = create(:admin_user, profile: build_profile(imoveis_permissions(create: false, edit: false), position: 761))
      habitation = create(:habitation, admin_user: owner)
      sign_in user

      get edit_admin_habitation_path(habitation)

      expect(response).to redirect_to(admin_habitations_path)
    end

    it "permite edição de imóvel alheio quando o perfil edita" do
      user = create(:admin_user, profile: build_profile(imoveis_permissions(create: false, edit: true)))
      owner = create(:admin_user, profile: build_profile(imoveis_permissions(create: false, edit: false), position: 762))
      habitation = create(:habitation, admin_user: owner)
      sign_in user

      get edit_admin_habitation_path(habitation)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "Leads · editar" do
    def leads_permissions(edit:)
      {
        "admin" => false,
        "dashboard" => { "view" => true },
        "leads" => { "view" => true, "edit" => edit, "delete" => false, "scope" => "all" }
      }
    end

    # Lead#status guarda o rótulo canônico ("Em Atendimento"), não a chave.
    # Antes desta fase o update só exigia :view + escopo do registro.
    it "bloqueia update de lead para quem só visualiza" do
      user = create(:admin_user, profile: build_profile(leads_permissions(edit: false)))
      lead = create(:lead, admin_user: user, status: :novo)
      sign_in user

      patch_lead(lead, lead: { status: "em_atendimento" })

      expect(lead.reload.status).to eq("Novo")
    end

    it "permite update de lead para quem edita" do
      user = create(:admin_user, profile: build_profile(leads_permissions(edit: true)))
      lead = create(:lead, admin_user: user, status: :novo)
      sign_in user

      patch_lead(lead, lead: { status: "em_atendimento" })

      expect(lead.reload.status).to eq("Em Atendimento")
    end
  end

  describe "Vocabulário" do
    it "desmembra manage em create/edit nos recursos migrados" do
      imoveis = Profile::RESOURCES.find { |res| res[:key] == "imoveis" }
      leads = Profile::RESOURCES.find { |res| res[:key] == "leads" }

      expect(imoveis[:actions]).to include("create", "edit")
      expect(imoveis[:actions]).not_to include("manage")

      expect(leads[:actions]).to include("create", "edit")
      expect(leads[:actions]).not_to include("manage")
    end

    it "mantém manage nos recursos ainda não desmembrados" do
      comercial = Profile::RESOURCES.find { |res| res[:key] == "comercial" }

      expect(comercial[:actions]).to include("manage")
      expect(Profile::ACTION_LABELS["manage"]).to eq("Gerenciar")
    end

    it "não concede create por herança de edit (nem o contrário)" do
      only_edit = build_profile(imoveis_permissions(create: false, edit: true))
      only_create = build_profile(imoveis_permissions(create: true, edit: false), position: 763)

      expect(only_edit.can?(:create, :imoveis)).to be(false)
      expect(only_create.can?(:edit, :imoveis)).to be(false)
    end

    it "renderiza as colunas Criar e Editar na matriz" do
      sign_in create(:admin_user, :admin, email: "ce-perm-#{SecureRandom.hex(6)}@salute.test")

      get new_admin_profile_path(axis: "vertical")

      matrix = Nokogiri::HTML(response.body).at_css("table.prof-matrix")
      headers = matrix.css("thead th[scope='col']").map { |th| th.text.strip }
      expect(headers).to include("Criar", "Editar")

      expect(matrix.css("input[name='profile[permissions][imoveis][create]']")).to be_present
      expect(matrix.css("input[name='profile[permissions][leads][create]']")).to be_present
      expect(matrix.css("input[name='profile[permissions][leads][edit]']")).to be_present
      # Comercial ainda não foi desmembrado: segue com o balde legado.
      expect(matrix.css("input[name='profile[permissions][comercial][manage]']")).to be_present
      expect(matrix.css("input[name='profile[permissions][comercial][create]']")).to be_empty
    end
  end
end
