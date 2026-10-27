module Integrations
  # Configuração pode ser preparada com a entrega pausada, sem ativar a conta.
  class StageConversionAvailability
    def initialize(tenant)
      @tenant = tenant
    end

    def state(provider)
      return :missing unless @tenant

      case provider.to_s
      when "google"
        settings = @tenant.webhook_settings.where(google_conversions_enabled: true).to_a
        settings = @tenant.webhook_settings.to_a if settings.empty?
        configured = settings.select { |setting| setting.encryption_ready? && setting.google_destination_url.to_s.start_with?("https://") }
        return :missing if configured.empty?

        configured.any? { |setting| setting.enabled? && setting.google_conversions_enabled? } ? :active : :paused
      when "meta"
        config = MetaConversionConfig.for_tenant(@tenant).first
        return :missing unless config && config.dataset_list.any? && config.sending_token.present?

        config.enabled? ? :active : :paused
      else
        :missing
      end
    rescue ActiveRecord::Encryption::Errors::Base
      :missing
    end
  end
end
