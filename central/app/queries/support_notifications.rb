# A leitura é pessoal e aponta para a mensagem recebida, não para o relógio do navegador.
class SupportNotifications
  def self.unread(staff)
    received = Support::Message.where(side: 'requester', internal: false, deleted_at: nil)
      .select('ticket_id, MAX(id) AS latest_id, MIN(id) AS first_id').group(:ticket_id)
    Support::Ticket.where.not(status: 'resolvido').includes(:account)
      .joins("INNER JOIN (#{received.to_sql}) received ON received.ticket_id = support_tickets.id")
      .joins(Support::Ticket.sanitize_sql_array(['LEFT JOIN support_notification_reads reads ON reads.ticket_id = support_tickets.id AND reads.staff_id = ?', staff.id]))
      .where('received.latest_id > COALESCE(reads.message_id, 0)')
      .select('support_tickets.*, received.latest_id, received.first_id')
  end
end
