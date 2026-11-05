require "rails_helper"

RSpec.describe "Consistência operacional dos leads", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  before { host! "localhost"; sign_in admin }

  it "atualiza a agenda desktop e mobile ao salvar um retorno via Turbo" do
    lead = create(:lead, tenant: tenant, admin_user: admin)
    headers = { "Accept" => Mime[:turbo_stream].to_s }

    post schedule_activity_admin_lead_path(lead),
         params: { activity_kind: "return", due_at: 1.day.from_now.iso8601, notes: "Revisar proposta" },
         headers: headers

    expect(response).to have_http_status(:ok)
    expect(lead.tasks.count).to eq(1)
    streams = Nokogiri::HTML.fragment(response.body)
    %w[desktop pwa].each do |variant|
      stream = streams.at_css("turbo-stream[action='replace'][target='#{variant}_operational_panel_lead_#{lead.id}']")
      expect(stream.at_css("#lead-#{variant}-agenda").text).to include("Retornar para o cliente", "Revisar proposta")
    end

    post schedule_activity_admin_lead_path(lead), params: { activity_kind: "" }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Selecione o tipo de atividade.")
    expect(response.body).not_to include('action="replace"')
  end

  it "envia o modal de tarefa da ficha com navegação completa e volta com a tarefa criada" do
    lead = create(:lead, tenant: tenant, admin_user: admin)
    get admin_lead_path(lead)
    form = Nokogiri::HTML(response.body).at_css("#lead-desktop-tarefas form.task-form-modal__form")
    expect(form["data-turbo"]).to eq("false")

    post admin_tasks_path, params: { task: { lead_id: lead.id, title: "Retorno pelo modal", kind: "follow_up" } },
         headers: { "HTTP_REFERER" => admin_lead_url(lead) }
    expect(response).to redirect_to(admin_lead_url(lead))
    follow_redirect!
    expect(Nokogiri::HTML(response.body).at_css("#lead-desktop-tarefas").text).to include("Retorno pelo modal")
  end

  it "registra conclusão e reabertura com autoria e exige motivo para reabrir" do
    lead = create(:lead, tenant: tenant, admin_user: admin)
    task = create(:task, lead: lead, admin_user: admin)

    patch complete_admin_task_path(task)
    expect(task.reload).to be_concluida
    patch reopen_admin_task_path(task), params: { reason: " " }
    expect(task.reload).to be_concluida

    2.times { patch reopen_admin_task_path(task), params: { reason: "Atualizar o fluxo" } }
    expect(task.reload).to be_pendente
    expect(task.completed_at).to be_nil
    events = lead.activities.where(kind: %w[task_completed task_reopened]).order(:id)
    expect(events.map(&:kind)).to eq(%w[task_completed task_reopened])
    expect(events.last.metadata).to include("actor_id" => admin.id, "task_id" => task.id, "reason" => "Atualizar o fluxo")

    get admin_lead_path(lead)
    agenda = Nokogiri::HTML(response.body).at_css("#lead-desktop-agenda")
    expect(agenda.text).to include("Concluir atividade", "Reaberta", "Atualizar o fluxo")
  end

  it "mantém tarefas concluídas consultáveis na ficha e preserva os retornos pendentes na agenda" do
    lead = create(:lead, tenant: tenant, admin_user: admin)
    create(:task, lead: lead, admin_user: admin, title: "Retorno em aberto")
    create(:task, lead: lead, admin_user: admin, title: "Retorno finalizado",
           description: "Passar o fluxo em 120 meses", status: "concluida", completed_at: Time.current)

    get admin_lead_path(lead)

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#lead-desktop-agenda").text).to include("Retorno em aberto")
    tasks = doc.at_css("#lead-desktop-tarefas")
    expect(tasks.text).to include("Retorno finalizado", "Concluída", "Passar o fluxo em 120 meses")
    expect(tasks.at_css(".lead-operational-section__actions .ax-badge").text).to eq("0")
  end

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
