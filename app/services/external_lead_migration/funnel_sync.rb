module ExternalLeadMigration
  class FunnelSync
    STATUS_ALIASES = {
      "pending" => "Aguardando Aceite",
      "under_negotiation" => "Em Atendimento",
      "em_negociacao" => "Em Atendimento",
      "converted" => "Concluido",
      "business_closed" => "Concluido",
      "done_deal" => "Concluido",
      "lost" => "Descartado",
      "archived" => "Descartado",
      "arquivado" => "Descartado",
      "closed" => "Concluido"
    }.freeze

    def self.status_for!(tenant:, payload:, fallback: nil, pipeline: nil)
      new(tenant:).status_for!(payload:, fallback:, pipeline:)
    end

    def self.ensure_source!(tenant:)
      new(tenant:).ensure_option!(category: "source", name: ExternalLeadIntegration::LEAD_ORIGIN)
    end

    def initialize(tenant:)
      @tenant = tenant
    end

    def status_for!(payload:, fallback: nil, pipeline: nil)
      attrs = extract_attributes(payload.to_h.deep_stringify_keys)
      candidate = attrs.dig("funnel_status", "name").presence ||
        attrs.dig("lead_status", "name").presence ||
        attrs["status"].presence
      alias_name = attrs.dig("lead_status", "alias").presence || attrs["status"].presence
      raw_name = candidate.presence || alias_name.presence || fallback
      return Lead.default_status(tenant:, pipeline:) if initial_status?(raw_name)

      name = normalize_status_name(raw_name)
      return Lead.default_status(tenant:) if name.blank?

      ensure_stage!(pipeline: pipeline || LeadPipeline.default_for(tenant:), name: name).name
    end

    def ensure_option!(category:, name:)
      normalized = AttributeOption.normalized_name_key(name)
      existing = tenant.attribute_options.where(context: "lead", category: category).detect do |option|
        AttributeOption.normalized_name_key(option.name) == normalized
      end
      return existing if existing

      tenant.attribute_options.create!(
        context: "lead",
        category: category,
        name: AttributeOption.sanitize_name(name)
      )
    end

    def ensure_stage!(pipeline:, name:)
      pipeline ||= ensure_default_pipeline!
      existing = LeadPipelineStage.matching_name(tenant:, pipeline:, name:)
      return existing if existing

      tenant.lead_pipeline_stages.create!(
        lead_pipeline: pipeline,
        name: LeadPipelineStage.sanitize_name(name)
      )
    end

    def ensure_default_pipeline!
      existing = LeadPipeline.default_for(tenant:)
      return existing if existing

      tenant.lead_pipelines.create!(
        name: "Principal",
        kind: "mixed",
        default_general: true,
        default_for_sale: true,
        default_for_rental: true
      )
    end

    private

    attr_reader :tenant

    def extract_attributes(payload)
      data = payload["data"]
      return data.first["attributes"].to_h if data.is_a?(Array) && data.first.is_a?(Hash)
      return data["attributes"].to_h if data.is_a?(Hash)
      return payload.dig("lead", "attributes").to_h if payload.dig("lead", "attributes").is_a?(Hash)
      return payload["attributes"].to_h if payload["attributes"].is_a?(Hash)

      payload
    end

    def normalize_status_name(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      STATUS_ALIASES[raw.parameterize(separator: "_")] || AttributeOption.sanitize_name(raw)
    end

    def initial_status?(value)
      value.to_s.parameterize(separator: "_").in?(Lead::INITIAL_STATUS_KEYS)
    end
  end
end
