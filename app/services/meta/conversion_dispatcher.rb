module Meta
  # Envia o evento configurado na etapa para leads Meta Ads da conta com CAPI ativa.
  class ConversionDispatcher
    def self.call(lead:, event_name:, value: nil, occurred_at: Time.current)
      return unless LeadPipelineStage::META_CONVERSION_EVENTS.key?(event_name) && lead&.tenant_id && lead.meta_ads_origin?

      config = MetaConversionConfig.for_tenant(lead.tenant).first
      return unless config&.active?

      MetaConversionJob.perform_later(
        lead.tenant_id,
        lead.id,
        event_name,
        event_id(lead.tenant_id, lead.id, event_name),
        occurred_at.iso8601,
        value&.to_f
      )
    end

    def self.event_id(tenant_id, lead_id, event_name)
      Digest::SHA1.hexdigest("unitymob-meta-capi:#{tenant_id}:#{lead_id}:#{event_name}")
    end
  end
end
