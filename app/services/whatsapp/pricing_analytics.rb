module Whatsapp
  class PricingAnalytics
    Result = Struct.new(:amount, :currency, :delivered, :message, :checked_at, keyword_init: true)
    class Unavailable < StandardError; end
    class PartnerBilling < Unavailable; end

    def self.call(tenant:, sender:, starts_on:, ends_on:)
      raise ArgumentError, "Número de outra conta" unless sender.tenant_id == tenant.id
      raise ArgumentError, "Período inválido" unless starts_on <= ends_on && starts_on >= 1.year.ago.to_date && ends_on <= Date.current

      token = sender.access_token
      unless sender.active? && sender.waba_id.to_s.match?(/\A[0-9]+\z/) && token.present?
        return Result.new(message: "Conecte este número à Meta para consultar a cobrança.")
      end
      key = ["whatsapp-pricing-v1", tenant.id, sender.id, sender.waba_id, sender.display_phone_number,
        Digest::SHA256.hexdigest(token), Time.zone.name, starts_on, ends_on]
      Rails.cache.fetch(key, expires_in: 10.minutes) do
        new(sender, token, starts_on, ends_on).call
      end
    end

    def initialize(sender, token, starts_on, ends_on)
      @sender, @token = sender, token
      @start = starts_on.in_time_zone.beginning_of_day.to_i
      @end = ends_on.next_day.in_time_zone.beginning_of_day.to_i
    end

    def call
      currency = get("", fields: "currency")["currency"]
      raise Unavailable, "A Meta não informou a moeda da cobrança." unless currency.to_s.match?(/\A[A-Z]{3}\z/)
      begin
        payload = pricing(%w[COST VOLUME])
      rescue PartnerBilling
        points = data_points(pricing(["VOLUME"]))
        return Result.new(currency: currency, delivered: volume(points), checked_at: Time.current,
          message: "A Meta bloqueou o custo porque esta conta é cobrada por parceiro. Consulte o parceiro para obter o valor oficial; nenhum valor foi estimado.")
      end
      points = data_points(payload)
      unless points.any? && points.all? { |point| point["cost"].is_a?(Numeric) && point["cost"] >= 0 }
        return Result.new(currency: currency, delivered: volume(points), checked_at: Time.current,
          message: "A Meta ainda não disponibilizou o custo completo deste período. Nenhum valor foi estimado.")
      end
      Result.new(amount: points.sum { |point| point["cost"].to_s.to_d }, currency: currency,
        delivered: volume(points), checked_at: Time.current)
    rescue Unavailable => error
      Result.new(currency: currency, message: error.message, checked_at: Time.current)
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError, Net::HTTPBadResponse, Net::ProtocolError, EOFError, IOError, HTTParty::Error
      Result.new(message: "Não foi possível consultar a Meta agora. Tente novamente mais tarde.", checked_at: Time.current)
    end

    private

    def pricing(metrics)
      get("/pricing_analytics", start: @start, end: @end, granularity: "DAILY",
        phone_numbers: [@sender.display_phone_number.gsub(/\D/, "")].to_json,
        dimensions: %w[PHONE PRICING_CATEGORY PRICING_TYPE].to_json, metric_types: metrics.to_json)
    end

    def get(path, query)
      response = HTTParty.get("#{CloudClient::GRAPH_HOST}/#{CloudClient.api_version}/#{@sender.waba_id}#{path}",
        headers: {"Authorization" => "Bearer #{@token}"}, query: query, timeout: 10)
      payload = JSON.parse(response.body, decimal_class: BigDecimal)
      raise Unavailable, "Resposta inválida da Meta." unless payload.is_a?(Hash)
      error = payload["error"]
      if error.is_a?(Hash) && error["error_subcode"].to_i == 2388184
        raise PartnerBilling, "Custo indisponível por cobrança via parceiro."
      end
      unless response.code.to_i.between?(200, 299) && error.nil?
        raise Unavailable, "A Meta não autorizou ou não concluiu a consulta da cobrança. Confira o acesso à conta WhatsApp."
      end
      raise Unavailable, "A Meta retornou um relatório parcial. Consulte um período menor." if payload.dig("paging", "next").present?
      payload
    end

    def data_points(payload)
      groups = payload["data"]
      raise Unavailable, "Resposta inválida da Meta." unless groups.is_a?(Array) && groups.all? { |group| group.is_a?(Hash) && group["data_points"].is_a?(Array) }
      points = groups.flat_map { |group| group["data_points"] }
      valid = points.all? do |point|
        point.is_a?(Hash) && point["start"].is_a?(Numeric) && point["end"].is_a?(Numeric) &&
          point["start"] >= @start && point["end"] <= @end &&
          point["phone_number"].to_s.delete_prefix("+") == @sender.display_phone_number.gsub(/\D/, "") &&
          point["volume"].is_a?(Integer) && point["volume"] >= 0
      end
      raise Unavailable, "A Meta retornou dados fora do número ou período solicitado." unless valid
      points
    end

    def volume(points)
      points.sum { |point| point.fetch("volume") } if points.any?
    end
  end
end
