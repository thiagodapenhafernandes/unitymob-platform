class Admin::TasksController < Admin::BaseController
  before_action -> { check_permission!(:view, :comercial) }, only: [:index]
  before_action -> { check_permission!(:manage, :comercial) }, only: [:create, :update, :complete, :destroy]
  before_action :set_task, only: [:update, :complete, :destroy]

  FILTERS = %w[pendentes hoje atrasadas semana concluidas todas legado].freeze

  def index
    @filter = params[:filter].presence_in(FILTERS) || "pendentes"
    scoped_tasks = task_scope
    base = @filter == "legado" ? scoped_tasks.external_legacy : scoped_tasks.operational_current
    @tasks = filtered(base, @filter).includes(:lead, :admin_user).ordered.limit(300)
    @counts = {
      pendentes: base.pendentes.count,
      hoje: base.hoje.count,
      atrasadas: base.atrasadas.count,
      semana: base.semana.count,
      legado: scoped_tasks.external_legacy.pendentes.count
    }
    @page_title = "Minhas Tarefas"
  end

  def create
    @task = current_tenant.tasks.new(task_params)
    @task.created_by = current_admin_user
    @task.admin_user ||= current_admin_user

    if @task.save
      LeadActivity.log!(lead: @task.lead, kind: "task_created", metadata: { task_id: @task.id, title: @task.title, due_at: @task.due_at }) if @task.lead_id
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_tasks_path, notice: "Tarefa criada." }
        format.turbo_stream do
          @task.lead ? render_lead_operational_turbo_stream(@task.lead, notice: "Tarefa criada.") : redirect_back(fallback_location: admin_tasks_path, notice: "Tarefa criada.")
        end
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_tasks_path, alert: @task.errors.full_messages.to_sentence }
        format.turbo_stream do
          @task.lead ? render_lead_operational_turbo_stream(@task.lead, alert: @task.errors.full_messages.to_sentence, status: :unprocessable_entity) : redirect_back(fallback_location: admin_tasks_path, alert: @task.errors.full_messages.to_sentence)
        end
      end
    end
  end

  def update
    if @task.update(task_params)
      LeadActivity.log!(lead: @task.lead, kind: "task_updated", metadata: { task_id: @task.id, title: @task.title, due_at: @task.due_at, by: current_admin_user&.name }) if @task.lead_id
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_tasks_path, notice: "Tarefa atualizada." }
        format.turbo_stream do
          @task.lead ? render_lead_operational_turbo_stream(@task.lead, notice: "Tarefa atualizada.") : redirect_back(fallback_location: admin_tasks_path, notice: "Tarefa atualizada.")
        end
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_tasks_path, alert: @task.errors.full_messages.to_sentence }
        format.turbo_stream do
          @task.lead ? render_lead_operational_turbo_stream(@task.lead, alert: @task.errors.full_messages.to_sentence, status: :unprocessable_entity) : redirect_back(fallback_location: admin_tasks_path, alert: @task.errors.full_messages.to_sentence)
        end
      end
    end
  end

  def complete
    @task.complete!(by: current_admin_user)
    respond_to do |format|
      format.html { redirect_back fallback_location: admin_tasks_path, notice: "Tarefa concluída." }
      format.turbo_stream do
        @task.lead ? render_lead_operational_turbo_stream(@task.lead, notice: "Tarefa concluída.") : redirect_back(fallback_location: admin_tasks_path, notice: "Tarefa concluída.")
      end
      format.json { render json: { id: @task.id, status: @task.status } }
    end
  end

  def destroy
    @task.destroy
    redirect_back fallback_location: admin_tasks_path, notice: "Tarefa removida."
  end

  private

  def filtered(base, filter)
    case filter
    when "hoje" then base.hoje
    when "atrasadas" then base.atrasadas
    when "semana" then base.semana
    when "concluidas" then base.concluidas
    when "todas" then base
    when "legado" then base
    else base.pendentes
    end
  end

  def task_scope
    ids = visible_owner_ids(:comercial)
    base = current_tenant.tasks
    return base if ids.nil?
    base.where(admin_user_id: ids)
  end

  def set_task
    @task = task_scope.find(params[:id])
  end

  def task_params
    permitted = [:title, :description, :kind, :due_at, :priority, :lead_id]
    permitted << :admin_user_id if can?(:manage, :comercial) && (tenant_owner? || owns_all_resource?(:comercial) || current_admin_user.can_view_team?(:comercial))
    attrs = params.require(:task).permit(permitted)
    restrict_owner_param_to_scope!(attrs, :comercial)
  end
end
