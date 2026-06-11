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

    def self.for_habitation(habitation, message: nil)
      new.for_habitation(habitation, message: message)
    end

    def config
      deep_merge(default_config, persisted_config)
    end

    def update!(params)
      payload = {
        "default_number" => normalize_phone(params[:default_number]),
        "rules" => {}
      }

      NEGOTIATION_TYPES.each_key do |key|
        rule_params = params.dig(:rules, key) || params.dig("rules", key) || {}
        payload["rules"][key] = {
          "number" => normalize_phone(rule_params[:number] || rule_params["number"]),
          "capture_enabled" => truthy?(rule_params[:capture_enabled] || rule_params["capture_enabled"])
        }
      end

      Setting.set(SETTING_KEY, payload.to_json, "Configuração dos botões de WhatsApp do site por tipo de negociação")
    end

    def for_habitation(habitation, message: nil)
      type = negotiation_type_for(habitation)
      rules = config.fetch("rules")
      rule = rules.fetch(type, {})
      number = rule["number"].presence || config["default_number"].presence || fallback_number

      {
        negotiation_type: type,
        negotiation_label: NEGOTIATION_TYPES.fetch(type),
        capture_required: rule.fetch("capture_enabled", true),
        phone_number: number,
        whatsapp_url: build_url(number, message.presence || default_message_for(habitation))
      }
    end

    private

    def persisted_config
      raw = Setting.get(SETTING_KEY, "{}").to_s
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

    def fallback_number
      normalize_phone(ContactSetting.instance.whatsapp_primary).presence || DEFAULT_PHONE
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
      "https://wa.me/#{normalize_phone(number)}?text=#{ERB::Util.url_encode(message.to_s)}"
    end

    def normalize_phone(value)
      digits = value.to_s.gsub(/\D/, "")
      return "" if digits.blank?

      digits.start_with?("55") ? digits : "55#{digits}"
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def deep_merge(base, override)
      base.deep_merge(override || {}) do |_key, old_value, new_value|
        new_value.nil? ? old_value : new_value
      end
    end
  end
end
