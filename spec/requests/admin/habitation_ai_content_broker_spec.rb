require "rails_helper"

RSpec.describe "Admin::Habitations conteúdo IA x corretor", type: :request do
  include Devise::Test::IntegrationHelpers

  def agent_profile
    Tenant.default.profiles.find_by!(key: "agent").tap do |p|
      p.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
  end

  before { host! "localhost" }

  it "bloqueia 'Gerar com IA' para o corretor e libera para o admin" do
    agent = create(:admin_user, email: "agent-ai-#{SecureRandom.hex(6)}@salute.test")
    agent.update!(profile: agent_profile)
    habitation = create(:habitation, admin_user: agent, exibir_no_site_flag: true,
                        codigo: "AI-#{SecureRandom.hex(4)}")

    sign_in agent
    post generate_ai_preview_admin_habitation_path(habitation),
         params: csrf_params_from_habitation(habitation)
    expect(response).to redirect_to(edit_admin_habitation_path(habitation.id, anchor: "features"))
    expect(flash[:alert]).to include("restrita ao administrador")

    admin = create(:admin_user, :admin, email: "admin-ai-#{SecureRandom.hex(6)}@salute.test")
    sign_in admin
    @csrf_token = nil
    post generate_ai_preview_admin_habitation_path(habitation),
         params: csrf_params_from_habitation(habitation)
    # admin passa pelo guard; sem token OpenAI cai no aviso de configurar, NÃO no de restrição
    expect(flash[:alert].to_s).not_to include("restrita ao administrador")
  end

  it "retorna sugestão com dados para preencher título e descrição no formulário" do
    admin = create(:admin_user, :admin, email: "admin-ai-fill-#{SecureRandom.hex(6)}@salute.test")
    habitation = create(:habitation, tenant: admin.tenant, admin_user: admin, codigo: "AI-FILL-#{SecureRandom.hex(4)}")
    suggestion = AiPropertySuggestion.create!(
      habitation: habitation,
      admin_user: admin,
      status: "pending",
      generated_title: "Apartamento frente mar pronto para morar",
      generated_description: "Primeiro parágrafo da descrição. Segundo parágrafo da descrição.",
      generated_seo_keywords: "frente mar, apartamento"
    )
    service = instance_double(Ai::PropertyContentService, generate_suggestion!: suggestion)

    allow(Ai::PropertyContentService).to receive(:connected?).and_return(true)
    allow(Ai::PropertyContentService).to receive(:new).with(habitation, admin_user: admin).and_return(service)

    sign_in admin
    post generate_ai_preview_admin_habitation_path(habitation),
         params: csrf_params_from_habitation(habitation),
         headers: {
           "Turbo-Frame" => ActionView::RecordIdentifier.dom_id(habitation, :ai_content_preview),
           "X-CSRF-Token" => csrf_token_from_habitation(habitation)
         }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    payload = document.at_css("[data-ai-preview-fill-title]")
    expect(payload["data-ai-preview-fill-title"]).to eq("Apartamento frente mar pronto para morar")
    expect(payload["data-ai-preview-fill-description-html"]).to include("<p>Primeiro parágrafo da descrição.")
    expect(payload["data-ai-preview-fill-seo-keywords"]).to eq("frente mar, apartamento")
    expect(response.body).to include("Sugestão gerada e carregada nos campos para revisão.")
    expect(response.body).not_to include("Título sugerido")
    expect(response.body).not_to include("Aplicar sugestão")
  end

  def csrf_params_from_habitation(habitation)
    token = csrf_token_from_habitation(habitation)
    token.present? ? { authenticity_token: token } : {}
  end

  def csrf_token_from_habitation(habitation)
    return @csrf_token if defined?(@csrf_token) && @csrf_token.present?

    get edit_admin_habitation_path(habitation)
    @csrf_token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content").to_s
  end
end
