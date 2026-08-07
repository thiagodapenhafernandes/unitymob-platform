require "rails_helper"

RSpec.describe "Admin::LeadPipelines", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "lead-pipeline-admin-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "cria funil no tenant atual com etapas iniciais" do
    expect {
      post admin_lead_pipelines_path,
           params: {
             lead_pipeline: {
               name: "Locação",
               kind: "rental",
               default_general: "1",
               default_for_sale: "1"
             },
             stages: {
               "0" => { name: "Entrada locação", description: "Primeiro contato", stage_type: "open" },
               "1" => { name: "Contrato fechado", stage_type: "won" },
               "2" => { name: "", stage_type: "lost" }
             }
           }
    }.to change { admin.tenant.lead_pipelines.count }.by(1)

    pipeline = admin.tenant.lead_pipelines.find_by!(name: "Locação")
    expect(pipeline).to be_default_for_rental
    expect(pipeline).not_to be_default_general
    expect(pipeline).not_to be_default_for_sale
    expect(pipeline.stages.ordered.pluck(:name, :stage_type)).to eq([
      ["Entrada locação", "open"],
      ["Contrato fechado", "won"]
    ])
    expect(response).to redirect_to(admin_lead_pipeline_leads_path(pipeline, view: "kanban"))
  end

  it "mantem etapa inicial padrao quando nenhuma etapa e informada" do
    post admin_lead_pipelines_path,
         params: {
           lead_pipeline: {
             name: "Personalizado",
             kind: "custom"
           }
         }

    pipeline = admin.tenant.lead_pipelines.find_by!(name: "Personalizado")
    expect(pipeline.stages.pluck(:name)).to include("Novo")
    expect(pipeline).not_to be_default_general
    expect(pipeline).not_to be_default_for_sale
    expect(pipeline).not_to be_default_for_rental
  end

  it "recalcula defaults automaticamente quando altera o tipo do funil" do
    pipeline = create(:lead_pipeline, tenant: admin.tenant, name: "Venda", kind: "custom")

    patch admin_lead_pipeline_path(pipeline),
          params: {
            lead_pipeline: {
              name: "Venda",
              kind: "sale",
              default_general: "1",
              default_for_rental: "1"
            }
          }

    expect(response).to redirect_to(admin_lead_pipeline_leads_path(pipeline, view: "kanban"))
    pipeline.reload
    expect(pipeline).to be_default_for_sale
    expect(pipeline).not_to be_default_general
    expect(pipeline).not_to be_default_for_rental
  end
end
