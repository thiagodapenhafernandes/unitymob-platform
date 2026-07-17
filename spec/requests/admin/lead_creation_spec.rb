require "rails_helper"

# Cadastro manual de lead pelo admin.
# Regra de propriedade (definida pelo produto):
#   - corretor mexe só nos próprios leads e vira dono do que cadastra;
#   - a cadeia de gestores até o admin da conta gerencia a subárvore, incluindo
#     atribuir o lead a outro corretor;
#   - perfil horizontal só alcança mais se for liberado na tela de perfis.
RSpec.describe "Admin lead creation", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.create!(name: "Tenant leads #{SecureRandom.hex(3)}", slug: "tenant-leads-#{SecureRandom.hex(3)}") }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before { host! "localhost" }

  def build_profile(permissions, position:)
    Profile.create!(
      tenant: tenant,
      name: "Perfil #{SecureRandom.hex(6)}",
      axis: Profile::AXES[:vertical],
      position: position,
      permissions: permissions
    )
  end

  def leads_permissions(create:, scope:, edit: true)
    {
      "admin" => false,
      "dashboard" => { "view" => true },
      "leads" => { "view" => true, "create" => create, "edit" => edit, "delete" => false, "scope" => scope }
    }
  end

  def valid_params(extra = {})
    { lead: { name: "Maria Cliente", phone: "47999990000", status: "Novo" }.merge(extra) }
  end

  def csrf_params_from_response
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content")
    token.present? ? { authenticity_token: token } : {}
  end

  def post_lead(params)
    get new_admin_lead_path
    post admin_leads_path, params: csrf_params_from_response.merge(params)
  end

  def last_tenant_lead
    tenant.leads.order(:id).last
  end

  describe "permissão" do
    it "bloqueia o cadastro para perfil sem create" do
      user = create(:admin_user, profile: build_profile(leads_permissions(create: false, scope: "own"), position: 800))
      sign_in user

      get new_admin_lead_path
      expect(response).not_to have_http_status(:ok)

      expect { post admin_leads_path, params: valid_params }.not_to change(Lead, :count)
    end

    it "permite o cadastro para perfil com create" do
      user = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "own"), position: 801))
      sign_in user

      get new_admin_lead_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "dono do lead" do
    it "grava o criador como dono" do
      user = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "own"), position: 802))
      sign_in user

      expect { post_lead(valid_params) }.to change(Lead, :count).by(1)

      expect(last_tenant_lead.admin_user_id).to eq(user.id)
    end

    # O corretor não pode "plantar" lead no nome de outro: mesmo forjando o
    # admin_user_id no request, o dono continua sendo ele.
    it "ignora admin_user_id forjado por quem tem escopo 'próprios'" do
      user = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "own"), position: 803))
      other = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "own"), position: 804))
      sign_in user

      post_lead(valid_params(admin_user_id: other.id))

      expect(last_tenant_lead.admin_user_id).to eq(user.id)
    end

    it "deixa o gestor atribuir o lead a um corretor da própria equipe" do
      manager = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "team"), position: 805))
      broker = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "own"), position: 806), manager: manager)
      sign_in manager

      post_lead(valid_params(admin_user_id: broker.id))

      expect(last_tenant_lead.admin_user_id).to eq(broker.id)
    end

    # Fora da subárvore o gestor não alcança: cai para ele mesmo em vez de
    # atribuir a um corretor que não é dele.
    it "não atribui a corretor fora da equipe do gestor" do
      manager = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "team"), position: 807))
      stranger = create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "own"), position: 808))
      sign_in manager

      post_lead(valid_params(admin_user_id: stranger.id))

      expect(last_tenant_lead.admin_user_id).to eq(manager.id)
    end
  end

  describe "campos do cadastro" do
    let(:user) { create(:admin_user, profile: build_profile(leads_permissions(create: true, scope: "all"), position: 809)) }

    before { sign_in user }

    it "grava status, origem, produto, tags e observações" do
      post_lead(valid_params(
        status: "Em Atendimento",
        origin: "Indicação",
        product: "Apartamento",
        lead_type: "Venda",
        tags: "investidor, urgente",
        notes: "Cliente quer visitar no sábado."
      ))

      lead = last_tenant_lead
      expect(lead.status).to eq("Em Atendimento")
      expect(lead.origin).to eq("Indicação")
      expect(lead.product).to eq("Apartamento")
      expect(lead.tags).to contain_exactly("investidor", "urgente")
      expect(lead.notes).to eq("Cliente quer visitar no sábado.")
    end

    it "usa 'Cadastro manual' como origem quando não informada" do
      post_lead(valid_params(origin: ""))

      expect(last_tenant_lead.origin).to eq("Cadastro manual")
    end

    it "vincula o imóvel de interesse pelo código" do
      habitation = create(:habitation, admin_user: user, codigo: "REF-#{SecureRandom.hex(4)}")

      post_lead(valid_params(property_code: habitation.codigo))

      expect(last_tenant_lead.property_id).to eq(habitation.id)
    end

    # Código inexistente não pode derrubar o cadastro, mas precisa avisar.
    it "cadastra e avisa quando o código do imóvel não existe" do
      expect {
        post_lead(valid_params(property_code: "NAO-EXISTE-999"))
      }.to change(Lead, :count).by(1)

      expect(last_tenant_lead.property_id).to be_nil
      expect(flash[:notice]).to include("nenhum imóvel com o código")
    end

    it "não vincula imóvel de outro tenant" do
      other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
      foreign = create(:habitation, tenant: other_tenant, codigo: "FOREIGN-#{SecureRandom.hex(4)}")

      post_lead(valid_params(property_code: foreign.codigo))

      expect(last_tenant_lead.property_id).to be_nil
    end

    it "devolve o formulário quando falta nome" do
      expect {
        post_lead(lead: { name: "", phone: "47999990000" })
      }.not_to change(Lead, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "registra o cadastro na timeline do lead" do
      post_lead(valid_params)

      expect(last_tenant_lead.activities.where(kind: "created")).to be_present
    end
  end
end
