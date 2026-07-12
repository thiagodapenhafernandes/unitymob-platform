class SeoAiGenerationJob < ApplicationJob
  queue_as :default

  def perform(seo_setting_id, tenant_id: nil)
    tenant = Tenant.find_by(id: tenant_id)
    raise ArgumentError, "Tenant obrigatório para geração SEO" if tenant.blank?

    seo_setting = tenant.seo_settings.find_by(id: seo_setting_id)
    return if seo_setting.blank?
    return if seo_setting.manual_mode?
    return unless Ai::SeoContentService.connected?

    Current.set(tenant: tenant) { Ai::SeoContentService.new(seo_setting).generate! }
  end
end
