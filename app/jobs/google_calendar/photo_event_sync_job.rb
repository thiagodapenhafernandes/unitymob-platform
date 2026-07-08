module GoogleCalendar
  class PhotoEventSyncJob < ApplicationJob
    queue_as :default

    def perform(habitation_id, tenant_id:)
      tenant = Tenant.find_by(id: tenant_id)
      return if tenant.blank?

      Current.set(tenant: tenant) do
        habitation = tenant.habitations.find_by(id: habitation_id)
        return if habitation.blank?

        PhotoEventSyncer.new(habitation: habitation, tenant: tenant).call
      end
    end
  end
end
