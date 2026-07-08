module Vista
  # Dispara Vista::ImportAgentsService em background (queue :sync) para não
  # bloquear o request HTTP — o serviço pagina a API e baixa avatares, podendo
  # levar minutos. Current não atravessa o ActiveJob: o tenant vai por argumento.
  class ImportAgentsJob < ApplicationJob
    queue_as :sync

    def perform(tenant_id:)
      tenant = Tenant.find(tenant_id)
      Current.set(tenant: tenant) do
        Vista::ImportAgentsService.call
      end
    end
  end
end
