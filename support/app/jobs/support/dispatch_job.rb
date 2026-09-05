class Support::DispatchJob < ActiveJob::Base
  queue_as { ENV.fetch("SUPPORT_QUEUE", "default") }

  def perform
    Support::Delivery.due.order(:id).limit(50).pluck(:id).each do |id|
      delivery = Support::Delivery.find(id)
      delivery.with_lock do
        next if delivery.delivered_at || delivery.failed_at || delivery.next_attempt_at.future?
        next if delivery.ticket_id && Support::Delivery.where(ticket_id: delivery.ticket_id, delivered_at: nil, failed_at: nil).where("id < ?", delivery.id).exists?
        begin
          Support::Transport.post(delivery.account, "/internal/support/v1/events", Support::Exchange.wire(delivery))
          delivery.update!(delivered_at: Time.current, last_error: nil)
        rescue ActiveStorage::FileNotFoundError, Support::Transport::DeliveryError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError => error
          attempts = delivery.attempts + 1
          terminal = error.is_a?(Support::Transport::DeliveryError) && [409, 422].include?(error.status)
          delivery.update!(failed_at: terminal ? Time.current : nil, attempts: attempts, next_attempt_at: Time.current + [2**[attempts, 10].min, 900].min.seconds, last_error: terminal ? "Destino recusou esta alteração; o conteúdo foi preservado." : error.class.name)
        end
      end
    end
    unless SupportDesk.central?
      Support::Message.where(notification_pending: true).limit(30).pluck(:id).each { |id| Support::NotifyJob.perform_later(id) }
    end
  end
end
