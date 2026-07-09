module InboundWebhooks
  class LeadReceiver
    Result = Struct.new(:lead, :errors, keyword_init: true) do
      def success?
        lead&.persisted?
      end
    end

    SENSITIVE_KEYS = %w[
      authenticity_token commit controller action utf8 token password secret
      webhook_secret access_token refresh_token api_key
    ].freeze

    class << self
      def call(token:, payload:, request:)
        new(token:, payload:, request:).call
      end
    end

    def initialize(token:, payload:, request:)
      @token = token
      @payload = normalize_hash(payload)
      @request = request
    end

    def call
      lead = token.admin_user.tenant.leads.new(lead_attributes.except(:tenant))

      if lead.save
        @token.record_received!
      end

      Result.new(lead:, errors: lead.errors.full_messages)
    end

    private

    attr_reader :token, :payload, :request

    def lead_attributes
      sanitized_payload = deep_filter(payload)
      filterable_payload = filterable_payload_from(sanitized_payload)
      tags = normalized_tags

      {
        tenant: token.admin_user.tenant,
        # NÃO pré-atribuir ao dono do token: o lead entra SEM corretor para as
        # regras de distribuição rodarem (o RoutingService só distribui quando
        # admin_user_id é nil). Quem recebeu via token fica auditado em
        # other_information (inbound_webhook_user_id/name).
        name: field_value("name", "nome", "client_name", "clientName"),
        email: field_value("email", "client_email", "clientEmail"),
        phone: Phones::Normalizer.call(field_value("phone", "telefone", "celular", "whatsapp", "client_phone", "clientPhone")),
        property_id: integer_value("property_id", "propertyId", "habitation_id", "habitationId"),
        source_url: field_value("source_url", "sourceUrl", "page_url", "pageUrl", "url"),
        lead_type: "webhook",
        origin: "webhook",
        product: field_value("product", "property_title", "propertyTitle", "imovel", "imóvel"),
        other_information: filterable_payload.merge(
          "webhook_payload" => sanitized_payload,
          "webhook_tags" => tags,
          "inbound_webhook_user_id" => token.admin_user_id,
          "inbound_webhook_user_name" => token.admin_user&.name,
          "inbound_webhook_endpoint" => "leads",
          "inbound_webhook_received_at" => Time.current.iso8601,
          "request_ip" => request&.remote_ip
        ).compact
      }.compact
    end

    def filterable_payload_from(sanitized_payload)
      nested_payload = sanitized_payload["data"] || sanitized_payload["lead"]
      return sanitized_payload unless nested_payload.is_a?(Hash)

      nested_payload.merge(sanitized_payload.except("data", "lead"))
    end

    def field_value(*keys)
      keys.each do |key|
        value = lookup(payload, key)
        return value.to_s.strip if value.present?
      end

      nil
    end

    def integer_value(*keys)
      value = field_value(*keys)
      return nil if value.blank?

      Integer(value, exception: false)
    end

    def normalized_tags
      raw = lookup(payload, "keywords") || lookup(payload, "tags") || lookup(payload, "webhook_tags") || lookup(payload, "webhookTags")
      Array.wrap(raw)
        .flat_map { |item| item.to_s.split(",") }
        .map { |item| item.strip.downcase }
        .reject(&:blank?)
        .uniq
    end

    def lookup(hash, key)
      return nil unless hash.is_a?(Hash)

      return hash[key] if hash.key?(key)
      symbol_key = key.to_sym
      return hash[symbol_key] if hash.key?(symbol_key)

      data = hash["data"] || hash[:data] || hash["lead"] || hash[:lead]
      return nil unless data.is_a?(Hash)

      data[key] || data[symbol_key]
    end

    def normalize_hash(value)
      if value.respond_to?(:to_unsafe_h)
        value.to_unsafe_h
      elsif value.respond_to?(:to_h)
        value.to_h
      else
        {}
      end
    end

    def deep_filter(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          next if SENSITIVE_KEYS.include?(key.to_s)

          result[key.to_s] = deep_filter(item)
        end
      when Array
        value.map { |item| deep_filter(item) }
      else
        value
      end
    end
  end
end
