class MetaConversionJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(tenant_id, lead_id, event_name, event_id, occurred_at_iso, value = nil)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant

    Current.set(tenant: tenant) do
      lead = tenant.leads.find_by(id: lead_id)
      return unless lead&.meta_ads_origin?

      config = MetaConversionConfig.for_tenant(tenant).first
      return unless config&.active?

      Meta::ConversionService.new(config).send_event(
        lead: lead,
        event_name: event_name,
        event_id: event_id,
        occurred_at: Time.zone.parse(occurred_at_iso.to_s) || Time.current,
        value: value
      )
    end
  end
end
