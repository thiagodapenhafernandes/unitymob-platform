module Vista
  class BackfillBrokersJob < ApplicationJob
    queue_as :sync

    # Current não atravessa o ActiveJob: o tenant vai por argumento.
    def perform(tenant_id:)
      tenant = Tenant.find(tenant_id)
      Current.set(tenant: tenant) do
        Vista::BackfillBrokersService.call
      end
    end
  end
end
