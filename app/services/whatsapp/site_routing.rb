module Whatsapp
  class SiteRouting
    SETTING_KEY = "whatsapp_site_routing".freeze
    DEFAULT_PHONE = "554733111067".freeze
    NEGOTIATION_TYPES = {
      "sale" => "Venda",
      "rent" => "Locação",
      "sale_rent" => "Venda e locação"
    }.freeze

    def self.config
      new.config
    end

    def self.update!(params)
      new.update!(params)
    end

    def self.for_habitation(habitation, message: nil, lead: nil, tenant: Current.tenant)
      new(tenant: tenant).for_habitation(habitation, message: message, lead: lead)
    end

    def initialize(tenant: Current.tenant)
      @tenant = tenant
    end

    def config
      deep_merge(default_config, persisted_config)
    end

    def update!(params)
      payload = {
        "default_number" => Phones::Normalizer.call(params[:default_number]).to_s,
        "rules" => {}
      }

      NEGOTIATION_TYPES.each_key do |key|
        rule_params = params.dig(:rules, key) || params.dig("rules", key) || {}
        payload["rules"][key] = {
          "number" => Phones::Normalizer.call(rule_params[:number] || rule_params["number"]).to_s,
          "capture_enabled" => truthy?(rule_params[:capture_enabled] || rule_params["capture_enabled"])
        }
      end

      Setting.set(SETTING_KEY, payload.to_json, "Configuração dos botões de WhatsApp do site por tipo de negociação", tenant: tenant)
    end

    def for_habitation(habitation, message: nil, lead: nil)
      type = negotiation_type_for(habitation)
      rule = routing_rule_for(type)
      number = rule.fetch("number")
      whatsapp_message = ContactSetting.instance(tenant: tenant).property_whatsapp_message_for(type, lead:, habitation:, fallback: message.presence || default_message_for(habitation))

      {
        negotiation_type: type,
        negotiation_label: NEGOTIATION_TYPES.fetch(type),
        capture_required: rule.fetch("capture_enabled", true),
        phone_number: number,
        whatsapp_message: whatsapp_message,
        whatsapp_url: build_url(number, whatsapp_message)
      }
    end

    private

    def persisted_config
      raw = Setting.tenant_get(SETTING_KEY, "{}", tenant: tenant).to_s
      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def default_config
      {
        "default_number" => fallback_number,
        "rules" => NEGOTIATION_TYPES.keys.index_with do
          {
            "number" => "",
            "capture_enabled" => true
          }
        end
      }
    end

    def routing_rule_for(type)
      integration = WhatsappBusinessIntegration.current(tenant)
      return integration_routing_rule_for(integration, type) if integration.persisted?

      rules = config.fetch("rules")
      legacy_rule = rules.fetch(type, {})
      {
        "number" => legacy_rule["number"].presence || config["default_number"].presence || fallback_number,
        "capture_enabled" => legacy_rule.fetch("capture_enabled", true)
      }
    end

    def integration_routing_rule_for(integration, type)
      {
        "number" => integration.phone_for(type).presence || fallback_number,
        "capture_enabled" => integration.requires_form_for?(type)
      }
    end

    def fallback_number
      Phones::Normalizer.call(ContactSetting.instance(tenant: tenant).whatsapp_primary).to_s.presence || DEFAULT_PHONE
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      DEFAULT_PHONE
    end

    def negotiation_type_for(habitation)
      return "sale" unless habitation

      sale = habitation.valor_venda_cents.to_i.positive? || habitation.status.to_s.match?(/venda/i)
      rent = habitation.valor_locacao_cents.to_i.positive? || habitation.status.to_s.match?(/aluguel|loca[cç][aã]o/i)

      return "sale_rent" if sale && rent
      return "rent" if rent

      "sale"
    end

    def default_message_for(habitation)
      return "Olá, gostaria de mais informações." unless habitation

      code = habitation.codigo.presence
      title = habitation.respond_to?(:display_title) ? habitation.display_title : habitation.titulo_anuncio
      "Olá, gostaria de mais informações sobre o imóvel #{title}#{code.present? ? " (Código: #{code})" : ""}."
    end

    def build_url(number, message)
      "https://wa.me/#{Phones::Normalizer.call(number)}?text=#{ERB::Util.url_encode(message.to_s)}"
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def deep_merge(base, override)
      base.deep_merge(override || {}) do |_key, old_value, new_value|
        new_value.nil? ? old_value : new_value
      end
    end

    attr_reader :tenant
  end
end
