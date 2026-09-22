# Gestão dos atendimentos abertos por botões de fluxo de resposta: quem atende quem, transferir e finalizar.
class Admin::WhatsappAttendancesController < Admin::BaseController
  requires_permission :view, :whatsapp_inbox, only: [:index]
  requires_permission :manage, :whatsapp_inbox, only: [:transfer, :finish]
  before_action :set_attendance, only: [:transfer, :finish]

  CLOSED_WINDOW = 7.days

  def index
    @status = params[:status].presence_in(%w[open closed]) || "open"
    base = attendance_scope
    scope = @status == "open" ? base.open_now.order(:opened_at) : base.where(status: "closed").where("closed_at >= ?", CLOSED_WINDOW.ago).order(closed_at: :desc)
    scope = scope.where(admin_user_id: params[:owner_id]) if params[:owner_id].present?
    @attendances = scope.includes(:admin_user, :closed_by, whatsapp_conversation: :lead).limit(200).to_a
    @counts = { open: base.open_now.count, closed: base.where(status: "closed").where("closed_at >= ?", CLOSED_WINDOW.ago).count }
    @owners = current_tenant.admin_users.where(id: base.where.not(admin_user_id: nil).select(:admin_user_id)).order(:name)
    @last_inbound = WhatsappMessage.inbound.where(whatsapp_conversation_id: @attendances.map(&:whatsapp_conversation_id)).group(:whatsapp_conversation_id).maximum(:created_at)
    @page_title = "Gestão de atendimentos"
  end

  def transfer
    target = @attendance.transfer_candidates.find_by(id: params[:to_admin_user_id])
    return redirect_back(fallback_location: admin_whatsapp_attendances_path, alert: "Escolha um colega válido para transferir.") unless target

    Whatsapp::AttendanceManager.transfer!(@attendance, to: target, by: current_admin_user)
    redirect_back fallback_location: admin_whatsapp_attendances_path, notice: "Atendimento transferido para #{target.name}."
  end

  def finish
    result = Whatsapp::AttendanceManager.finish!(@attendance, admin_user: current_admin_user)
    redirect_back fallback_location: admin_whatsapp_attendances_path, notice: "Atendimento finalizado.", alert: result.warning
  end

  private

  # Só os atendimentos de conversas que o usuário pode ver (próprios, equipe ou todos, conforme o escopo do perfil).
  def attendance_scope
    WhatsappAttendance.where(tenant_id: current_tenant.id, whatsapp_conversation_id: WhatsappConversation.visible_to(current_admin_user).select(:id))
  end

  def set_attendance
    @attendance = attendance_scope.open_now.find(params[:id])
  end
end
