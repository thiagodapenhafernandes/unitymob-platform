class NotificationsController < ApplicationController
  before_action { head :forbidden unless current_staff.operator? }

  def index
    unread = SupportNotifications.unread(current_staff)
    render json: { count: unread.count(:all), items: unread.order('received.latest_id DESC').limit(30).map { |ticket|
      { ticket_id: ticket.id, message_id: ticket.latest_id,
        title: "##{ticket.id} · #{ticket.requester_name}", account: ticket.account.name,
        kind: ticket.origin == 'receptivo' && ticket.latest_id == ticket.first_id ? 'Novo chamado' : 'Nova resposta do cliente',
        url: support_tickets_path(q: "##{ticket.id}", selected: ticket.id) }
    } }
  end

  def create
    message = Support::Message.where(side: 'requester', internal: false, deleted_at: nil).find(params[:message_id])
    # O lock no colaborador serializa cliques de abas diferentes sem regredir o cursor.
    current_staff.with_lock do
      read = SupportNotificationRead.find_or_initialize_by(staff: current_staff, ticket_id: message.ticket_id)
      read.update!(message_id: [read.message_id.to_i, message.id].max)
    end
    head :no_content
  end
end
