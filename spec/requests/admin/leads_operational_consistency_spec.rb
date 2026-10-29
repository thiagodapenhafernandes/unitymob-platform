require "rails_helper"

RSpec.describe "Consistência operacional dos leads", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  before { host! "localhost"; sign_in admin }

  it "não cria colunas legadas vazias e preserva uma coluna antiga com lead" do
    pipeline = LeadPipeline.ensure_default!(tenant: tenant)
    configured = create(:lead_pipeline_stage, lead_pipeline: pipeline, name: "Etapa configurada")
    tenant.lead_pipeline_stages.where(name: "Em Atendimento").destroy_all
    old = create(:lead, tenant: tenant, name: "Lead antigo preservado", lead_pipeline: pipeline)
    old.update_columns(status: "Etapa antiga com registro", lead_pipeline_stage_id: nil)
    get admin_leads_path(view: "kanban")
    doc = Nokogiri::HTML(response.body)
    columns = doc.css('[data-lead-kanban-status]').map { |node| node['data-lead-kanban-status'] }
    expect(columns).to include(configured.name, "Etapa antiga com registro")
    expect(columns).not_to include("Em Atendimento")
    expect(old.reload.status).to eq("Etapa antiga com registro")
  end

  it "oculta arquivados nas abas, lista, cards e paginação, mas permite consultar o histórico" do
    pipeline = create(:lead_pipeline, tenant: tenant)
    stage = create(:lead_pipeline_stage, lead_pipeline: pipeline, name: "Arquivo operacional", stage_type: "archived")
    lead = create(:lead, tenant: tenant, admin_user: admin, lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name, name: "Cliente arquivado único")
    get admin_leads_path(view: "list", lead_pipeline_id: pipeline.id)
    expect(Nokogiri::HTML(response.body).css(".lead-list").text).not_to include(lead.name)
    get list_page_admin_leads_path(format: :json, lead_pipeline_id: pipeline.id)
    expect(response.parsed_body['total']).to eq(0)
    get kanban_column_admin_leads_path(status: stage.name, lead_pipeline_id: pipeline.id)
    expect(response.parsed_body['loaded_count']).to eq(0)
    get kanban_column_admin_leads_path(column_status: stage.name, lead_pipeline_id: pipeline.id, status: [stage.name])
    expect(response.parsed_body['loaded_count']).to eq(1)
    expect(lead.reload).to be_persisted
  end

  it "não reintroduz etapas ocultas quando um corretor não tem nenhuma etapa visível" do
    pipeline = create(:lead_pipeline, tenant: tenant)
    stage = create(:lead_pipeline_stage, lead_pipeline: pipeline, name: "Somente administradores")
    stage.create_policy!(tenant: tenant, visible_to_roles: ["admin"])
    broker = create(:admin_user, tenant: tenant, role: :editor)
    controller = Admin::LeadsController.new
    controller.define_singleton_method(:current_tenant) { tenant = pipeline.tenant; tenant }
    controller.define_singleton_method(:current_admin_user) { broker }
    controller.instance_variable_set(:@selected_pipeline, pipeline)
    expect(controller.send(:lead_status_options_for_selected_context)).to eq([])
    controller.instance_variable_set(:@status_filters, [stage.name])
    expect(controller.send(:lead_statuses_for_kanban, tenant.leads)).to eq([])
  end
end
