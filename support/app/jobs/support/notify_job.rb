class Support::NotifyJob < ActiveJob::Base
  queue_as { ENV.fetch("SUPPORT_QUEUE", "default") }
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(message_id)
    return if SupportDesk.central?
    message = Support::Message.find(message_id)
    message.with_lock do
      return unless message.notification_pending?
      ticket = message.ticket
      user = AdminUser.find_by(id: ticket.requester_id, tenant_id: ticket.account.local_tenant_id, active: true)
      if user
        Current.set(tenant: user.tenant) do
          Notifications::PushDispatcher.deliver(admin_user_id: user.id, title: "Resposta ao chamado", body: ticket.subject, url: "/admin/support/tickets/#{ticket.id}", tag: "support-#{ticket.uid}")
        end
      end
      message.update_columns(notification_pending: false, notified_at: Time.current)
    end
  end
end
