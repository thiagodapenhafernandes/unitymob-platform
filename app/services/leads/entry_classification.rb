module Leads
  # Classifica a consulta atual, sem usar o histórico ou o nome da campanha como modalidade.
  class EntryClassification
    SALE = /\b(venda|vender|comprar|compra|sale)\b/
    RENT = /\b(aluguel|alugar|locacao|locar|rent|rental)\b/
    ADMINISTRATIVE = /\b(financeiro|segunda via|boleto|rescisao|suporte administrativo)\b|\b(solicitar|solicito|preciso de|pedido de|agendar)\s+(uma\s+)?manutencao\b/

    def initialize(lead, message: nil)
      @lead, @message = lead, message
    end

    def nature
      return :administrative if normalize(@message ? @message.body : @lead.product).match?(ADMINISTRATIVE) || administrative_attendance?
      return :commercial unless @lead.whatsapp_service_contact?
      business_type ? :commercial : :unknown
    end

    def business_type
      return @business_type if defined?(@business_type)
      @business_type = resolve_business_type
    end

    private

    def resolve_business_type
      explicit = info["business_type"] || info["negotiation_type"]
      explicit ||= info["c2s_business_type"] if @lead.external_lead_integration_id.present?
      explicit ||= @lead.attribution_data.to_h["business_type"]
      normalized = normalize(explicit)
      return :venda if %w[sale venda compra].include?(normalized)
      return :locacao if %w[rent rental locacao aluguel].include?(normalized)
      return :ambos if %w[sale_rent ambos].include?(normalized)

      property = @lead.tenant.habitations.find_by(id: @lead.property_id) if @lead.property_id
      if property
        return {"sale" => :venda, "rent" => :locacao, "sale_rent" => :ambos}[property.whatsapp_negotiation_type]
      end
      sale, rent = text.match?(SALE), text.match?(RENT)
      return :ambos if sale && rent
      return :venda if sale
      return :locacao if rent
    end

    def info
      @lead.other_information.to_h
    end

    def normalize(value)
      I18n.transliterate(value.to_s).downcase.strip
    end

    def text
      @text ||= begin
        referral = @message ? @message.referral.to_h : info.dig("whatsapp_entry", "referral").to_h
        normalize([@lead.product, source_url_signal, info["rd_station_conversion_identifier"],
          referral["headline"], referral["body"], @message&.body].compact.join(" "))
      end
    end

    def source_url_signal
      uri = URI.parse(@lead.source_url.to_s)
      query = Rack::Utils.parse_nested_query(uri.query).slice("transaction_type", "business_type", "negotiation_type")
      [uri.path, query.values].join(" ")
    rescue URI::InvalidURIError, Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError
      ""
    end

    def administrative_attendance?
      return false unless @message
      attendances = @message.whatsapp_conversation.attendances.open_now
      attendances.administrative.exists? || attendances.joins(:distribution_rule)
        .where(distribution_rules: {distribution_mode: DistributionRule.distribution_modes[:attendance]}).exists?
    end
  end
end
