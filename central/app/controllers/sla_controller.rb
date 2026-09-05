class SlaController < ApplicationController
  before_action { head :forbidden unless current_staff.admin? }
  def index
    @from = Date.iso8601(params[:from].presence || 30.days.ago.to_date.iso8601).in_time_zone.beginning_of_day
    @to = [Date.iso8601(params[:to].presence || Date.current.iso8601).in_time_zone.end_of_day, Time.current].min
    raise ArgumentError if @to < @from || @to - @from > 366.days
    @staffs = Staff.order(:name)
    @accounts = Support::Account.order(:name)
    scope = Support::Ticket.where(id: Support::TicketEvent.where(kind: 'received', occurred_at: @from..@to).select(:ticket_id))
    scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
    scope = scope.where(id: Support::TicketEvent.where('staff_id = :id OR assignee_id = :id', id: params[:staff_id]).select(:ticket_id)) if params[:staff_id].present?
    @page = [params[:page].to_i, 1].max
    @total = scope.count
    @tickets = scope.includes(:account).order(id: :desc).limit(50).offset((@page - 1) * 50).to_a
    @legacy_count = Support::Ticket.where.not(id: Support::TicketEvent.where(kind: 'received').select(:ticket_id)).count
    @people = @staffs
    @people = @people.where(role: params[:role]) if Staff::ROLES.include?(params[:role])
    @people = @people.where(id: params[:staff_id]) if params[:staff_id].present?
    @policies = Support::Ticket::PRIORITIES.map { |priority| SlaPolicy.find_or_initialize_by(priority: priority) }
    @report = Support::SlaReport.new(tickets: scope, people: @people, from: @from, to: @to)
    @metrics = @report.metrics
    @policy_changes = SlaPolicyChange.includes(:staff).order(occurred_at: :desc).limit(20)
    @sessions = StaffSession.includes(:staff).where(started_at: @from..@to).order(started_at: :desc).limit(100)
    @sessions = @sessions.where(staff_id: @people.select(:id))
  rescue Date::Error, ArgumentError
    redirect_to sla_path, alert: 'Escolha um período válido de até 366 dias.'
  end

  def update
    SlaPolicy.transaction do
      Support::Ticket::PRIORITIES.each do |priority|
        raw = params.require(:policies).fetch(priority)
        raise ActionController::ParameterMissing, priority unless raw.is_a?(ActionController::Parameters)
        attrs = raw.permit(:first_response_minutes, :resolution_minutes)
        policy = SlaPolicy.find_or_initialize_by(priority: priority)
        policy.assign_attributes(attrs)
        changes = policy.changes
        policy.save!
        SlaPolicyChange.create!(staff: current_staff, priority: priority, changeset: changes, occurred_at: Time.current) if changes.any?
      end
    end
    redirect_to sla_path, notice: 'Metas salvas. Valem para novos chamados e novas alterações de prioridade; o histórico permanece preservado.'
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing, KeyError
    redirect_to sla_path, alert: 'Informe prazos em minutos maiores que zero, ou deixe em branco para não definir uma meta.'
  end
end
