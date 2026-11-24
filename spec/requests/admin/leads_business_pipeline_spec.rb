require "rails_helper"

RSpec.describe "Funil do lead por tipo de negócio", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:sale) { LeadPipeline.ensure_default!(tenant: admin.tenant) }
  let!(:sale_stage) { create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: sale, name: "Proposta venda") }
  let!(:rental) do
    admin.tenant.lead_pipelines.update_all(default_for_rental: false)
    create(:lead_pipeline, tenant: admin.tenant, kind: "rental", default_for_rental: true)
  end
  let!(:rental_stage) { create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: rental, name: "Proposta locação") }
  let!(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin, lead_pipeline: sale, lead_pipeline_stage: sale_stage, status: sale_stage.name, other_information: { "business_type" => "venda" }, skip_automatic_routing: true) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe o tipo de negócio e permite escolher as etapas sem acesso às configurações" do
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('select[name="lead[business_type]"] option[value="diaria"]')).to be_present
    expect(document.at_css('[data-lead-pipeline-stage-select-stages-value]')).to be_present
  end

  it "mostra na barra as etapas do funil vinculado ao lead" do
    lead.update_columns(lead_pipeline_id: rental.id, lead_pipeline_stage_id: rental_stage.id, status: rental_stage.name)
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    steps = Nokogiri::HTML(response.body).css(".lead-funnel-step").map { |node| node.text.strip }
    expect(steps).to include(rental_stage.name)
    expect(steps).not_to include(sale_stage.name)
  end

  it "mantém a etapa equivalente ao alterar somente o tipo" do
    equivalent = create(:lead_pipeline_stage, tenant: admin.tenant, lead_pipeline: rental, name: sale_stage.name)
    patch admin_lead_path(lead), params: { lead: { business_type: "locacao" } }
    expect(response).to have_http_status(:redirect)
    expect(lead.reload.lead_pipeline_stage).to eq(equivalent)
    expect(lead.lead_pipeline).to eq(rental)
  end

  it "exige escolher a etapa quando não existe equivalente" do
    patch admin_lead_path(lead), params: { lead: { business_type: "locacao" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("deve ser escolhida")
    expect(lead.reload.lead_pipeline).to eq(sale)
  end

  it "exige etapa ao corrigir um vínculo antigo incompatível sem mudar a modalidade" do
    lead.update_columns(lead_pipeline_id: rental.id, lead_pipeline_stage_id: rental_stage.id, status: rental_stage.name)
    patch admin_lead_path(lead), params: { lead: { business_type: "venda" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.lead_pipeline).to eq(rental)
  end

  it "salva a etapa escolhida no novo funil" do
    patch admin_lead_path(lead), params: { lead: { business_type: "locacao", lead_pipeline_stage_id: rental_stage.id, status: rental_stage.name } }
    expect(response).to have_http_status(:redirect)
    expect(lead.reload.lead_pipeline_stage).to eq(rental_stage)
  end

  it "não expõe nem aceita etapas restritas ao administrador para um corretor" do
    profile = admin.tenant.profiles.find_by!(key: "agent")
    profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    broker = create(:admin_user, tenant: admin.tenant, profile: profile)
    lead.update_columns(admin_user_id: broker.id)
    create(:lead_pipeline_stage_policy, tenant: admin.tenant, lead_pipeline_stage: rental_stage, visible_to_roles: ["admin"])
    sign_out admin
    sign_in broker

    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    node = Nokogiri::HTML(response.body).at_css('[data-lead-pipeline-stage-select-stages-value]')
    stages = JSON.parse(node["data-lead-pipeline-stage-select-stages-value"])
    expect(stages.fetch(rental.id.to_s)).to be_empty

    patch admin_lead_path(lead), params: { lead: { business_type: "locacao", lead_pipeline_stage_id: rental_stage.id, status: rental_stage.name } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.lead_pipeline).to eq(sale)
  end

  it "define o funil do cadastro manual pelo tipo e não pelo funil informado" do
    post admin_leads_path, params: { lead: { name: "Cliente locação", phone: "47988776655", business_type: "locacao", lead_pipeline_id: sale.id } }
    expect(response).to have_http_status(:redirect)
    created = admin.tenant.leads.order(:id).last
    expect(created.business_type).to eq("locacao")
    expect(created.lead_pipeline).to eq(rental)
  end
end
