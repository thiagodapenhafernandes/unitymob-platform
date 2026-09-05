class OutreachController < ApplicationController
  before_action { head :forbidden unless current_staff.operator? }
  rescue_from Support::Transport::DeliveryError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError do
    request.format.json? ? render(json: {error: 'Não foi possível consultar a conta. Tente novamente.'}, status: :bad_gateway) : redirect_to(support_tickets_path, alert: 'A conta não respondeu. Nenhum chamado foi enviado.')
  end
  def users
    render json: Support::Transport.post(account, '/internal/support/v1/recipients', {q: params[:q].to_s.first(100)})
  end
  def create
    target = Support::Transport.post(account, '/internal/support/v1/recipients', {id: params[:requester_id]}).fetch('users').find { |u| u['id'] == params[:requester_id] }
    return redirect_to(support_tickets_path, alert: 'Selecione um usuário ativo da conta.') unless target
    kind = params[:outreach_kind].to_s
    return head :unprocessable_entity unless %w[informativo solicitacao critico].include?(kind)
    ticket = nil
    Support::Ticket.transaction do
      ticket = account.tickets.create!(origin: 'ativo', outreach_kind: kind, subject: params[:subject], requester_id: target['id'], requester_name: target['name'], requester_email: target['email'],
        status: 'aguardando_usuario', priority: kind == 'critico' ? 'alta' : 'normal', assignee_id: current_staff.id, assignee_name: current_staff.name,
        intake: Support::Ticket::QUESTIONS.keys.index_with { 'Contato iniciado pela equipe de suporte.' })
      message = ticket.messages.create!(side: 'support', author: current_staff.name, author_staff_id: current_staff.id, body: params[:body])
      Support::Timeline.record!(ticket, 'received')
      Support::Timeline.record!(ticket, 'support_message', staff: current_staff)
      ticket.update!(revision: 1, first_response_at: Time.current)
      Support::Exchange.enqueue(ticket, message: message, command: 'outreach')
    end
    redirect_to support_tickets_path(selected: ticket.id), notice: 'Chamado salvo e encaminhado ao usuário. A entrega pode ser acompanhada na conversa.'
  rescue ActiveRecord::RecordInvalid => error
    redirect_to support_tickets_path, alert: error.record.errors.full_messages.to_sentence
  end
  private
  def account = @account ||= Support::Account.where(active: true).find(params[:account_id])
end
