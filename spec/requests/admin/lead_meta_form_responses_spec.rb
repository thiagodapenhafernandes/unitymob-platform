require "rails_helper"

RSpec.describe "Respostas das campanhas no lead", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe perguntas e todas as respostas escapadas no desktop e no mobile" do
    lead = create(:lead, tenant: admin.tenant, admin_user: admin, product: "9846 | Locação", other_information: {
      "meta_leadgen_id" => "meta-view", "field_data" => [
        { "name" => "você_está_buscando_imóvel_para:", "values" => ["nos_próximos_30_dias"] },
        { "name" => "preferências", "values" => ["Sacada", "Garagem", "<script>alert(1)</script>"] }
      ] })
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    [".lead-pwa-detail", "#lead-attendance"].each do |selector|
      content = document.at_css(selector).text
      expect(content).to include("Respostas do formulário Meta", "Você está buscando imóvel para:", "Nos próximos 30 dias", "Sacada", "Garagem")
    end
    expect(response.body).not_to include("<script>alert(1)</script>")
  end

  it "não expõe respostas de outra conta" do
    private_answer = "Resposta privada #{SecureRandom.hex(8)}"
    other = Tenant.create!(name: "Outra conta Meta", slug: "other-meta-form-view")
    lead = create(:lead, tenant: other, other_information: { "meta_leadgen_id" => "private-meta",
      "field_data" => [{ "name" => "Pergunta privada", "values" => [private_answer] }] })
    get admin_lead_path(lead), as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(private_answer)
  end

  it "respeita o acesso do corretor aos seus próprios leads" do
    lead = create(:lead, tenant: admin.tenant, admin_user: admin,
      other_information: { "meta_leadgen_id" => "restricted", "field_data" => [{ "name" => "Pergunta", "values" => ["Resposta restrita"] }] })
    agent = create(:admin_user, tenant: admin.tenant)
    agent.profile.update!(permissions: { "leads" => { "view" => true, "scope" => "own" } })
    agent.update!(horizontal_profile: nil)
    sign_in agent
    get admin_lead_path(lead)
    expect(response).to redirect_to(admin_leads_path)
    expect(response.body).not_to include("Resposta restrita")
  end

  ["text/html", Mime[:turbo_stream].to_s].each do |accept|
    it "preserva as respostas escapadas ao renderizar uma atualização inválida em #{accept}" do
      pipeline = create(:lead_pipeline, tenant: admin.tenant)
      stage = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: pipeline, name: "Triagem")
      create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: stage,
        qualification_enabled: true, qualification_options: %w[qualified])
      lead = create(:lead, tenant: admin.tenant, admin_user: admin, lead_pipeline: pipeline,
        lead_pipeline_stage: stage, status: stage.name, other_information: {
          "meta_leadgen_id" => "invalid-update-form", "field_data" => [
            { "name" => "Preferências", "values" => ["Sacada", "<script>alert(1)</script>"] }
          ] })

      patch admin_lead_path(lead), params: { lead: { manager_qualification_status: "disqualified" } },
        headers: { "ACCEPT" => accept }

      expect(response).to have_http_status(:unprocessable_entity)
      document = Nokogiri::HTML(response.body)
      [".lead-pwa-detail", "#lead-attendance"].each do |selector|
        expect(document.at_css(selector).text).to include("Respostas do formulário Meta", "Preferências", "Sacada")
      end
      expect(response.body).to include("&lt;script&gt;")
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(lead.reload.manager_qualification_status).to be_nil
    end
  end

end
