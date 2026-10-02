module Portal
  # Normaliza o payload do webhook de leads do Grupo OLX
  # (developers.grupozap.com/webhooks/integration_leads.html) para os
  # atributos de criação do Lead. Retorna nil quando o payload não tem o
  # mínimo para identificar o lead (originLeadId) — descarte permanente,
  # nunca retry.
  class GrupozapLead
    ORIGIN = "grupo_zap".freeze
    CHANNEL = "portal".freeze

    def initialize(payload)
      @payload = payload.is_a?(Hash) ? payload : {}
    end

    def self.call(payload)
      new(payload).normalize
    end

    def normalize
      origin_lead_id = @payload["originLeadId"].to_s.strip
      return nil if origin_lead_id.blank?

      {
        origin_lead_id: origin_lead_id,
        listing_code: @payload["clientListingId"].to_s.strip.presence,
        origin_listing_id: @payload["originListingId"].to_s.strip.presence,
        name: @payload["name"].to_s.strip.presence,
        email: @payload["email"].to_s.strip.presence,
        phone: normalized_phone,
        message: @payload["message"].to_s.strip.presence,
        temperature: @payload["temperature"].to_s.strip.presence,
        lead_type: extra_data["leadType"].to_s.strip.presence,
        transaction_type: @payload["transactionType"].to_s.strip.presence,
        lead_origin: @payload["leadOrigin"].to_s.strip.presence || "Grupo OLX",
        mcmv: mcmv_data,
        raw: @payload
      }
    end

    private

    def extra_data
      @payload["extraData"].is_a?(Hash) ? @payload["extraData"] : {}
    end

    def normalized_phone
      full = @payload["phoneNumber"].to_s.strip.presence ||
             [@payload["ddd"], @payload["phone"]].map { |part| part.to_s.strip }.join.presence
      return nil if full.blank?

      Phones::Normalizer.call(full).presence || full
    end

    def mcmv_data
      mcmv = extra_data["mcmv"]
      mcmv.is_a?(Hash) ? mcmv : nil
    end
  end
end
