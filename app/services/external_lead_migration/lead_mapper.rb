module ExternalLeadMigration
  class LeadMapper
    PROVIDER_KEY = "external_lead_migration".freeze

    def initialize(payload)
      @payload = payload.to_h.deep_stringify_keys
      @entry = normalize_entry(@payload)
      @attributes = @entry.fetch("attributes", {}).to_h
    end

    def external_lead_id
      @entry["id"].presence ||
        @attributes["id"].presence ||
        @payload["lead_id"].presence ||
        @payload["id"].presence
    end

    def external_internal_id
      integer_value(@entry["internal_id"].presence || @attributes["internal_id"])
    end

    def lead_attributes(integration:, historical:)
      customer = hash_at("customer")
      product = hash_at("product")
      seller = hash_at("seller")
      tags = tags_from(@attributes["tags"])
      status = mapped_status(tenant: integration.tenant)
      pipeline = pipeline_for(tenant: integration.tenant, product:)
      property_id = habitation_id_for(tenant: integration.tenant, product:)

      attrs = {
        tenant: integration.tenant,
        external_lead_integration: integration,
        lead_pipeline: pipeline,
        external_lead_id: external_lead_id,
        external_internal_id: external_internal_id,
        external_last_synced_at: Time.current,
        distribution_rule: integration.distribution_rule,
        admin_user: integration.local_user_for_seller(seller),
        property_id: property_id,
        name: customer["name"].presence || @attributes["name"].presence || "Lead externo",
        email: customer["email"].presence || @attributes["email"],
        phone: Phones::Normalizer.call(customer["phone"].presence || customer["phone_global"].presence || @attributes["phone"]),
        client_name: customer["name"].presence || @attributes["name"],
        client_email: customer["email"].presence || @attributes["email"],
        client_phone: Phones::Normalizer.call(customer["phone"].presence || customer["phone_global"].presence || @attributes["phone"]),
        client_external_id: customer["id"],
        agent_name: seller["name"],
        agent_email: seller["email"],
        agent_phone: Phones::Normalizer.call(seller["phone"]),
        agent_external_id: seller["id"],
        event_name: event_name,
        lead_type: "webhook",
        origin: ExternalLeadIntegration::LEAD_ORIGIN,
        source_url: @attributes["url"].presence || @attributes["source_url"],
        product: product_description(product),
        status: ExternalLeadMigration::FunnelSync.status_for!(tenant: integration.tenant, payload: @payload, fallback: status, pipeline:),
        attribution_channel: attribution_channel,
        attribution_source: attribution_source,
        attribution_data: attribution_data(product:),
        notes: notes,
        custom_answers: custom_answers,
        other_information: other_information(tags:, customer:, product:, seller:)
      }.compact

      created_at = parse_time(@attributes["created_at"])
      attrs[:created_at] = created_at if historical && created_at
      attrs
    end

    def closable?(tenant: Current.tenant)
      event_name.to_s.include?("close") || mapped_status(tenant:).in?(%w[Descartado Concluido])
    end

    def scheduled_actions
      Array.wrap(@entry["schedulated_actions"].presence || @attributes["schedulated_actions"]).filter_map do |action|
        action.to_h.presence
      end
    end

    def messages
      Array.wrap(@entry["messages"].presence || @attributes["messages"]).filter_map do |message|
        message.to_h.presence
      end
    end

    def log_entries
      Array.wrap(@attributes["log"].presence || @entry["log"]).filter_map do |entry|
        entry.to_h.presence
      end
    end

    def first_message
      @entry["first_message"].presence || @attributes["first_message"]
    end

    private

    def normalize_entry(payload)
      data = payload["data"]
      return normalize_entry(data.first) if data.is_a?(Array) && data.first.is_a?(Hash)
      return data if data.is_a?(Hash) && data["attributes"].is_a?(Hash)
      return payload["lead"] if payload["lead"].is_a?(Hash) && payload["lead"]["attributes"].is_a?(Hash)
      return payload["lead"] if payload["lead"].is_a?(Hash)

      payload
    end

    def hash_at(key)
      @attributes[key].is_a?(Hash) ? @attributes[key] : {}
    end

    def mapped_status(tenant: Current.tenant)
      return "Descartado" if archived?
      return "Concluido" if done_deal?

      status = @attributes.dig("lead_status", "alias").presence ||
        @attributes.dig("lead_status", "name").presence ||
        @attributes["status"].presence ||
        @payload["hook_action"].to_s.delete_prefix("on_")

      ExternalLeadMigration::FunnelSync::STATUS_ALIASES[status.to_s.parameterize(separator: "_")] || status.presence || Lead.default_status(tenant:)
    end

    def notes
      [
        @attributes["observation"],
        first_message,
        messages.first.to_h["body"]
      ].compact_blank.join("\n\n").presence
    end

    def custom_answers
      custom = @entry["custom_attributes"]
      return [] unless custom.present?

      case custom
      when Array
        custom.map do |item|
          item = item.to_h
          { "key" => item["name"].presence || item["key"], "answer" => item["value"].presence || item["answer"] }.compact
        end
      when Hash
        custom.map { |key, value| { "key" => key, "answer" => value } }
      else
        []
      end
    end

    def other_information(tags:, customer:, product:, seller:)
      @payload.merge(
        "external_lead_payload" => @entry,
        "external_lead_id" => external_lead_id,
        "external_internal_id" => external_internal_id,
        "external_lead_customer" => customer,
        "external_lead_product" => product,
        "external_lead_seller" => seller,
        "webhook_tags" => ([ExternalLeadIntegration::WEBHOOK_TAG] + tags).uniq,
        "source" => PROVIDER_KEY,
        "external_lead_synced_at" => Time.current.iso8601
      ).compact
    end

    def attribution_data(product:)
      {
        "provider" => PROVIDER_KEY,
        "external_lead_id" => external_lead_id,
        "external_internal_id" => external_internal_id,
        "lead_source" => hash_at("lead_source"),
        "channel" => hash_at("channel"),
        "facebook" => @entry["facebook_attributes"].presence || @attributes["facebook_attributes"],
        "company" => hash_at("company"),
        "from_hierarchy_company" => @attributes["from_hierarchy_company"],
        "external_created_at" => @attributes["external_created_at"],
        "product" => product,
        "archive_details" => @attributes["archive_details"],
        "done_details" => @attributes["done_details"],
        "lost_reasons" => @attributes["lost_reasons"]
      }.compact
    end

    def attribution_channel
      channel = hash_at("channel")
      channel["name"].presence || channel["alias"].presence || @attributes["channel"].to_s.presence || ExternalLeadIntegration::LEAD_ORIGIN
    end

    def attribution_source
      lead_source = hash_at("lead_source")
      channel = hash_at("channel")
      lead_source["name"].presence || lead_source["alias"].presence || channel["name"].presence || ExternalLeadIntegration::LEAD_ORIGIN
    end

    def product_description(product)
      [
        product["description"].presence || @attributes["description"],
        product.dig("real_estate_detail", "negotiation_name"),
        product["city"],
        product["neighbourhood"]
      ].compact_blank.join(" · ").presence
    end

    def pipeline_for(tenant:, product:)
      LeadPipeline.default_for(tenant:, business_type: business_type_for(product:))
    end

    def business_type_for(product:)
      text = [
        product.dig("real_estate_detail", "negotiation_name"),
        product["negotiation_name"],
        product["description"],
        @attributes["description"],
        @payload["hook_action"]
      ].compact.join(" ").parameterize(separator: "_")

      return "rental" if text.match?(/locacao|aluguel|alugar|rental/)
      return "sale" if text.match?(/venda|comprar|sale/)

      nil
    end

    def habitation_id_for(tenant:, product:)
      ref = product["prop_ref"].presence || product["reference"].presence || product["id"].presence
      return nil if ref.blank?

      tenant.habitations.where(codigo: ref.to_s.strip).pick(:id)
    end

    def archived?
      details = @attributes["archive_details"]
      details.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(details["archived"])
    end

    def done_deal?
      details = @attributes["done_details"]
      (details.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(details["done"])) ||
        @attributes["done_deal_at"].present?
    end

    def tags_from(value)
      Array.wrap(value)
        .flat_map { |item| item.is_a?(Hash) ? item.values_at("name", "id") : item }
        .flat_map { |item| item.to_s.split(",") }
        .map { |item| item.strip.downcase }
        .reject(&:blank?)
        .uniq
    end

    def event_name
      @payload["hook_action"].presence || @payload["event"].presence || "external_lead_sync"
    end

    def integer_value(value)
      Integer(value, exception: false)
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
