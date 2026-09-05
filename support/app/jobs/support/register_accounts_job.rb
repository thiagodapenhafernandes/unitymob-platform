class Support::RegisterAccountsJob < ActiveJob::Base
  queue_as { ENV.fetch("SUPPORT_QUEUE", "default") }

  def perform(tenant_id = nil)
    return unless Support::Registration.enabled?
    tenants = tenant_id ? Tenant.where(id: tenant_id) : Tenant.active
    tenants.find_each do |tenant|
      begin
        Support::Registration.sync(tenant)
      rescue Support::Transport::DeliveryError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError => error
        # A recorrência recupera contas novas e existentes sem bloquear o cadastro.
        Rails.logger.warn("[support] registro pendente tenant_id=#{tenant.id} error=#{error.class.name}")
      end
    end
  end
end
