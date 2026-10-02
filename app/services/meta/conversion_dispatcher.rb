module Meta
  # Ponto único de disparo do loop CRM -> Meta (Conversions API). Marcos fixos
  # (qualificado, visita, venda) via milestone; etapas do funil via event_name
  # direto do mapeamento da etapa. Só leads de origem Meta Ads e só contas com
  # config CAPI ativa; o event_id estável (um por lead por evento) faz a Meta
  # dedupar reenvios e caminhos duplos (ex.: proposta aceita + etapa de venda).
  class ConversionDispatcher
    EVENTS = {
      qualified: "QualifiedLead",
      visit_done: "Schedule",
      sale: "Purchase"
    }.freeze

    # milestone (marcos fixos) ou event_name direto (mapeamento por etapa).
    def self.call(lead:, milestone: nil, event_name: nil, value: nil, occurred_at: Time.current)
      event_name ||= EVENTS[milestone&.to_sym]
      return unless event_name && EVENTS.value?(event_name) && lead&.tenant_id && lead.meta_ads_origin?

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
