class Admin::TasksController < Admin::BaseController
  before_action -> { check_permission!(:view, :comercial) }, only: [:index]
  before_action -> { check_permission!(:manage, :comercial) }, only: [:create, :update, :complete, :destroy]
  before_action :set_task, only: [:update, :complete, :destroy]

  FILTERS = %w[pendentes hoje atrasadas semana concluidas todas].freeze

  def index
    @filter = params[:filter].presence_in(FILTERS) || "pendentes"
    base = task_scope
    @tasks = filtered(base, @filter).includes(:lead, :admin_user).ordered.limit(300)
    @counts = {
      pendentes: base.pendentes.count,
      hoje: base.hoje.count,
      atrasadas: base.atrasadas.count,
      semana: base.semana.count
    }
    @page_title = "Minhas Tarefas"
  end

  def create
    @task = Task.new(task_params)
    @task.created_by = current_admin_user
    @task.admin_user ||= current_admin_user

    if @task.save
      LeadActivity.log!(lead: @task.lead, kind: "task_created", metadata: { task_id: @task.id, title: @task.title, due_at: @task.due_at }) if @task.lead_id
      redirect_back fallback_location: admin_tasks_path, notice: "Tarefa criada."
    else
      redirect_back fallback_location: admin_tasks_path, alert: @task.errors.full_messages.to_sentence
    end
  end

  def update
    if @task.update(task_params)
      redirect_back fallback_location: admin_tasks_path, notice: "Tarefa atualizada."
    else
      redirect_back fallback_location: admin_tasks_path, alert: @task.errors.full_messages.to_sentence
    end
  end

  def complete
    @task.complete!(by: current_admin_user)
    respond_to do |format|
      format.html { redirect_back fallback_location: admin_tasks_path, notice: "Tarefa concluída." }
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
    else base.pendentes
    end
  end

  def task_scope
    ids = visible_owner_ids(:comercial)
    return Task.all if ids.nil?
    Task.where(admin_user_id: ids)
  end

  def set_task
    @task = task_scope.find(params[:id])
  end

  def task_params
    permitted = [:title, :description, :kind, :due_at, :priority, :lead_id]
    permitted << :admin_user_id if can?(:manage, :comercial) && (current_admin_user.admin? || owns_all_resource?(:comercial) || current_admin_user.can_view_team?(:comercial))
    params.require(:task).permit(permitted)
  end
end
