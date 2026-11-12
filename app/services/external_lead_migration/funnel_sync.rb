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

    MIRROR_STAGE_NAMES = {
      "new_lead" => ["Novo Lead", "Novo"],
      "in_attendance" => ["Em Atendimento", "Em Atendimento | Qualificado"],
      "scheduled_visit" => ["Visita agendada", "Agenda | Visita", "Visita/Contato"],
      "done_visit" => ["Visita Realizada", "Visita/Contato"],
      "created_offer" => ["Proposta criada", "Proposta"],
      "archived" => ["Arquivado", "Desqualificado | Arquivar", "Descartado"],
      "converted" => ["Negócio fechado", "Ganho", "Concluido"]
    }.freeze

    def self.mirrored_stage_attributes(integration:, payload:, pipeline:)
      new(tenant: integration.tenant).mirrored_stage_attributes(integration:, payload:, pipeline:)
    end

    def mirrored_stage_attributes(integration:, payload:, pipeline:)
      attrs = extract_attributes(payload.to_h.deep_stringify_keys)
      boolean = ActiveModel::Type::Boolean.new
      base = attrs.dig("lead_status", "alias").to_s
      key = if boolean.cast(attrs.dig("archive_details", "archived")) || base.in?(%w[lost archived finished])
        "archived"
      elsif boolean.cast(attrs.dig("done_details", "done")) || attrs["done_deal_at"].present? || base.in?(%w[converted business_closed done_deal])
        "converted"
      else
        value = attrs.dig("funnel_status", "status").presence || attrs.dig("funnel_status", "name").presence
        LeadPipelineStage.normalized_name_key(value.presence || base)
      end
      key = { "under_negotiation" => "in_attendance", "em_negociacao" => "in_attendance", "em_atendimento" => "in_attendance", "new" => "new_lead" }.fetch(key, key)
      key = MIRROR_STAGE_NAMES.find { |_key, values| values.any? { |name| LeadPipelineStage.normalized_name_key(name) == key } }&.first || key
      names = MIRROR_STAGE_NAMES[key]
      mapping_keys = [key, attrs.dig("funnel_status", "name"), attrs.dig("funnel_status", "status"), attrs.dig("lead_status", "name"), base]
      explicit = mapping_keys.compact_blank.filter_map { |value| integration.mapped_stage_for(LeadPipelineStage.normalized_name_key(value)) }.first
      return unless names || explicit

      stages = pipeline ? tenant.lead_pipeline_stages.active.where(lead_pipeline: pipeline).to_a : []
      stage = explicit
      if key.in?(%w[archived converted])
        type = key == "archived" ? %w[archived lost] : %w[won]
        stage = nil if stage && !stage.stage_type.in?(type)
        stages = stages.select { |candidate| candidate.stage_type.in?(type) }
      else
        stage = nil if stage && stage.stage_type != "open"
        stages = stages.select { |candidate| candidate.stage_type == "open" }
      end
      stage ||= Array(names).filter_map do |name|
        stages.find { |candidate| LeadPipelineStage.normalized_name_key(candidate.name) == LeadPipelineStage.normalized_name_key(name) }
      end.first
      stage ||= stages.find { |candidate| candidate.name.parameterize(separator: "_").start_with?("em_atendimento_") } if key == "in_attendance"
      stage ||= stages.first if key.in?(%w[archived converted])
      { status: stage&.name || names&.first, lead_pipeline: stage&.lead_pipeline || pipeline, lead_pipeline_stage: stage }
    end

    def self.status_for!(tenant:, payload:, fallback: nil, pipeline: nil, auto_create: true)
      new(tenant:).status_for!(payload:, fallback:, pipeline:, auto_create:)
    end

    def self.ensure_source!(tenant:)
      new(tenant:).ensure_option!(category: "source", name: ExternalLeadIntegration::LEAD_ORIGIN)
    end

    def initialize(tenant:)
      @tenant = tenant
    end

    def status_for!(payload:, fallback: nil, pipeline: nil, auto_create: true)
      attrs = extract_attributes(payload.to_h.deep_stringify_keys)
      candidate = attrs.dig("funnel_status", "name").presence ||
        attrs.dig("lead_status", "name").presence ||
        attrs["status"].presence
      alias_name = attrs.dig("lead_status", "alias").presence || attrs["status"].presence
      raw_name = candidate.presence || alias_name.presence || fallback
      return Lead.default_status(tenant:, pipeline:) if initial_status?(raw_name)

      name = normalize_status_name(raw_name)
      return Lead.default_status(tenant:) if name.blank?

      pipeline ||= LeadPipeline.default_for(tenant:)
      existing_stage = LeadPipelineStage.matching_name(tenant:, pipeline:, name:)
      return existing_stage.name if existing_stage
      return name if mapped_legacy_status?(raw_name, name)
      return Lead.default_status(tenant:, pipeline:) unless auto_create

      ensure_stage!(pipeline:, name: name).name
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

    def mapped_legacy_status?(raw_name, normalized_name)
      key = raw_name.to_s.parameterize(separator: "_")
      STATUS_ALIASES.key?(key) || normalized_name.in?(Lead::LEGACY_STATUSES)
    end
  end
end
