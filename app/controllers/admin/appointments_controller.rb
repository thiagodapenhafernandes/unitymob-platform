class Admin::AppointmentsController < Admin::BaseController
  before_action -> { check_permission!(:view, :comercial) }, only: [:index]
  before_action -> { check_permission!(:manage, :comercial) }, only: [:create, :update, :destroy]
  before_action :set_appointment, only: [:update, :destroy]

  def index
    @view = params[:view].presence_in(%w[semana dia lista]) || "semana"
    @date = parse_date(params[:date])
    scope = appointment_scope.includes(:lead, :habitation, :admin_user)

    case @view
    when "dia"
      @appointments = scope.for_day(@date).ordered
    when "lista"
      @appointments = scope.upcoming.limit(200)
    else
      @week_start = @date.beginning_of_week
      @week_end = @date.end_of_week
      @appointments = scope.between(@week_start.beginning_of_day, @week_end.end_of_day).ordered
      @days = (@week_start..@week_end).to_a
      @appointments_by_day = @appointments.group_by { |a| a.starts_at.to_date }
    end
    @page_title = "Agenda"
  end

  def create
    @appointment = current_tenant.appointments.new(appointment_params)
    @appointment.admin_user ||= current_admin_user

    if @appointment.save
      LeadActivity.log!(lead: @appointment.lead, kind: "appointment_created", metadata: appointment_meta) if @appointment.lead_id
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_appointments_path, notice: "Compromisso agendado." }
        format.turbo_stream do
          @appointment.lead ? render_lead_operational_turbo_stream(@appointment.lead, notice: "Compromisso agendado.") : redirect_back(fallback_location: admin_appointments_path, notice: "Compromisso agendado.")
        end
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_appointments_path, alert: @appointment.errors.full_messages.to_sentence }
        format.turbo_stream do
          @appointment.lead ? render_lead_operational_turbo_stream(@appointment.lead, alert: @appointment.errors.full_messages.to_sentence, status: :unprocessable_entity) : redirect_back(fallback_location: admin_appointments_path, alert: @appointment.errors.full_messages.to_sentence)
        end
      end
    end
  end

  def update
    was_done = @appointment.realizado?
    if @appointment.update(appointment_params)
      LeadActivity.log!(lead: @appointment.lead, kind: "appointment_updated", metadata: appointment_meta.merge(by: current_admin_user&.name)) if @appointment.lead_id
      if !was_done && @appointment.realizado? && @appointment.lead_id
        LeadActivity.log!(lead: @appointment.lead, kind: "appointment_done", metadata: appointment_meta)
      end
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_appointments_path, notice: "Compromisso atualizado." }
        format.turbo_stream do
          @appointment.lead ? render_lead_operational_turbo_stream(@appointment.lead, notice: "Compromisso atualizado.") : redirect_back(fallback_location: admin_appointments_path, notice: "Compromisso atualizado.")
        end
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_appointments_path, alert: @appointment.errors.full_messages.to_sentence }
        format.turbo_stream do
          @appointment.lead ? render_lead_operational_turbo_stream(@appointment.lead, alert: @appointment.errors.full_messages.to_sentence, status: :unprocessable_entity) : redirect_back(fallback_location: admin_appointments_path, alert: @appointment.errors.full_messages.to_sentence)
        end
      end
    end
  end

  def destroy
    @appointment.destroy
    redirect_back fallback_location: admin_appointments_path, notice: "Compromisso removido."
  end

  private

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    Date.current
  end

  def appointment_scope
    ids = visible_owner_ids(:comercial)
    base = current_tenant.appointments
    return base if ids.nil?
    base.where(admin_user_id: ids)
  end

  def set_appointment
    @appointment = appointment_scope.find(params[:id])
  end

  def appointment_meta
    { appointment_id: @appointment.id, title: @appointment.title, starts_at: @appointment.starts_at, kind: @appointment.kind }
  end

  def appointment_params
    permitted = [:title, :kind, :starts_at, :ends_at, :location, :status, :notes, :lead_id, :habitation_id]
    permitted << :admin_user_id if tenant_owner? || owns_all_resource?(:comercial) || current_admin_user.can_view_team?(:comercial)
    attrs = params.require(:appointment).permit(permitted)
    restrict_owner_param_to_scope!(attrs, :comercial)
  end
end
