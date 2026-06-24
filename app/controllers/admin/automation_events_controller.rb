class Admin::AutomationEventsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :automacoes) }
  before_action :set_event, only: [:reprocess, :ignore]

  def index
    @status = params[:status].presence_in(AutomationEvent::STATUSES)
    @event_name = params[:event].presence_in(Automation::EventCatalog.names)
    @source = params[:source].to_s.strip.presence
    @q = params[:q].to_s.strip

    @status_counts = AutomationEvent.group(:status).count
    @event_counts = AutomationEvent.group(:name).count
    @source_options = AutomationEvent.where.not(source: [nil, ""]).distinct.order(:source).pluck(:source)
    @failed_count = @status_counts.fetch("failed", 0)
    @pending_count = @status_counts.fetch("pending", 0)
    @processed_count = @status_counts.fetch("processed", 0)

    @events = filtered_events.paginate(page: params[:page], per_page: 30)
    @page_title = "Eventos da Automação"
  end

  def reprocess
    Automation::EventOperator.reprocess!(@event, by: current_admin_user)
    redirect_back fallback_location: admin_automation_events_path, notice: "Evento reenfileirado para processamento."
  rescue => e
    redirect_back fallback_location: admin_automation_events_path, alert: e.message
  end

  def ignore
    Automation::EventOperator.ignore!(@event, reason: params[:reason], by: current_admin_user)
    redirect_back fallback_location: admin_automation_events_path, notice: "Evento marcado como ignorado."
  rescue => e
    redirect_back fallback_location: admin_automation_events_path, alert: e.message
  end

  private

  def set_event
    @event = AutomationEvent.find(params[:id])
  end

  def filtered_events
    scope = AutomationEvent.includes(:lead, :automation_runs, :automation_executions).recent
    scope = scope.where(status: @status) if @status.present?
    scope = scope.where(name: @event_name) if @event_name.present?
    scope = scope.where(source: @source) if @source.present?

    if @q.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      scope = scope.left_outer_joins(:lead).where(
        "automation_events.idempotency_key ILIKE :q OR automation_events.name ILIKE :q OR leads.name ILIKE :q OR leads.email ILIKE :q OR leads.phone ILIKE :q",
        q: pattern
      )
    end

    scope
  end
end
