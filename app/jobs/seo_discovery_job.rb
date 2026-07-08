class SeoDiscoveryJob < ApplicationJob
  queue_as :sync

  # As páginas SEO atendem o site público (um por deploy): roda sob o tenant
  # público para escopar imóveis e Settings por conta, sem agregar dados
  # cross-tenant.
  def perform(generate_ai: true)
    Current.set(tenant: Tenant.public_for) do
      next unless Seo::DiscoveryService.enabled?

      Seo::DiscoveryService.new(generate_ai: generate_ai).call
    end
  end
end
