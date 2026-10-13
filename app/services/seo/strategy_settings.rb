module Seo
  # Fonte única de escrita da estratégia de SEO.
  # Usada por Admin::AiIntegrationsController (aba Conteúdo).
  class StrategySettings
    def self.save!(auto_inventory:, auto_apply:, auto_ai:, discovery:, prompt:, tenant: Current.tenant)
      Setting.set(PageTracker::AUTO_INVENTORY_SETTING, auto_inventory ? "1" : "0", "Criar SEO automaticamente por acesso", tenant: tenant)
      Setting.set(PageTracker::AUTO_APPLY_SETTING, auto_apply ? "1" : "0", "Aplicar SEO técnico automaticamente no público", tenant: tenant)
      Setting.set(PageTracker::AUTO_AI_SETTING, auto_ai ? "1" : "0", "Gerar SEO com IA automaticamente", tenant: tenant)
      DiscoveryService.save_enabled!(discovery, tenant: tenant)
      Ai::SeoContentService.save_instructions!(prompt, tenant: tenant)
    end
  end
end
