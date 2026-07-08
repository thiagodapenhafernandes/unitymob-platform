# Adesão de apresentação no atendimento WhatsApp (compliance, só leitura).
# Fonte unificada: WhatsappMessages carimbadas com presentation_card_id — cobre
# envios COM e SEM lead, com formato (texto/imagem), corretor e conversa.
class Admin::PresentationAuditLogsController < Admin::BaseController
  before_action -> { check_permission!(:view, :access_audit) }

  def index
    scope = WhatsappMessage.where(tenant_id: current_tenant.id)
                           .where.not(presentation_card_id: nil)
                           .includes(:admin_user, :presentation_card, whatsapp_conversation: :lead)
                           .order(created_at: :desc)

    scope = scope.where(admin_user_id: params[:admin_user_id]) if params[:admin_user_id].present?
    scope = scope.where("whatsapp_messages.created_at >= ?", parsed_date(params[:start_date]).beginning_of_day) if parsed_date(params[:start_date])
    scope = scope.where("whatsapp_messages.created_at <= ?", parsed_date(params[:end_date]).end_of_day) if parsed_date(params[:end_date])

    @logs = scope.paginate(page: params[:page], per_page: 40)
    stats = scope.except(:order, :limit, :offset, :includes)
    @total_sent = stats.count
    @distinct_brokers = stats.distinct.count(:admin_user_id)
    @with_photo = stats.where(msg_type: "image").count
    @without_lead = stats.joins(:whatsapp_conversation).where(whatsapp_conversations: { lead_id: nil }).count
    @available_users = current_tenant.admin_users.account_members.order(:name)
  end

  private

  def parsed_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
