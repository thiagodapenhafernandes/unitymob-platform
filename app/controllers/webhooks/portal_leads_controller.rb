module Webhooks
  # Recebe leads do Grupo OLX (ZAP, VivaReal, Imovelweb) via webhook.
  # Herda de ActionController::Base (não de ApplicationController) para não
  # executar o pipeline público — mesmo padrão do Webhooks::MetaController.
  #
  # Autenticação: Basic Auth com a SECRET_KEY por CRM
  # (developers.grupozap.com/webhooks/security.html), configurada via
  # Setting "grupozap_secret_key" ou ENV GRUPOZAP_SECRET_KEY. Ela identifica
  # o emissor, NUNCA o tenant: a conta dona resolve no job pelo código do
  # imóvel (clientListingId). Responde 2xx após enfileirar; o retry real
  # fica no job (idempotente por originLeadId).
  class PortalLeadsController < ActionController::Base
    skip_forgery_protection

    RATE_LIMIT = 120

    def grupozap
      integration = nil
      if params[:route_key].present?
        integration = PortalIntegration.find_by(lead_route_key: params[:route_key], portal: PortalIntegration::GRUPOZAP_PORTALS)
        return head(:not_found) unless integration
        return head(:unauthorized) unless valid_gateway_signature?
        return head(:conflict) unless integration.enabled? && integration.leads_enabled?
      else
        return head(:unauthorized) unless valid_secret_key?
      end
      return head(:too_many_requests) unless within_rate_limit?

      payload = parsed_body
      if payload["originLeadId"].to_s.strip.blank?
        return render json: { error: "originLeadId ausente" }, status: :unprocessable_entity
      end

      if payload["leadOrigin"] != "MCMV_OLX" && payload["clientListingId"].to_s.strip.blank?
        return render json: { error: "clientListingId ausente" }, status: :unprocessable_entity
      end

      if integration
        PortalLeadProcessingJob.perform_later(payload, integration.id)
      else
        PortalLeadProcessingJob.perform_later(payload)
      end
      head :ok
    end

    private

    def valid_gateway_signature?
      secret = Portal::LeadGatewayClient.forwarding_secret
      return false if secret.blank? || request.headers["X-Unitymob-Gateway-Provider"] != "grupozap"

      # Bind the signature to this integration, not only to the lead body.
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{params[:route_key]}\n#{request.raw_post}")}"
      ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Unitymob-Gateway-Signature"].to_s)
    end

    def valid_secret_key?
      configured = Setting.get(PortalIntegration::GRUPOZAP_SECRET_KEY, ENV["GRUPOZAP_SECRET_KEY"]).to_s
      return false if configured.blank?

      provided = basic_password
      return false if provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(provided, configured)
    rescue ArgumentError
      false
    end

    def basic_password
      header = request.headers["Authorization"].to_s
      return nil unless header.start_with?("Basic ")

      decoded = Base64.strict_decode64(header.delete_prefix("Basic ").strip)
      _user, _sep, password = decoded.partition(":")
      password.presence
    rescue ArgumentError
      nil
    end

    def parsed_body
      body = request.raw_post.to_s
      return {} if body.blank?

      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def within_rate_limit?
      key = "portal_lead_webhook_rate:#{request.remote_ip}:grupozap"
      current = Rails.cache.read(key).to_i
      return false if current >= RATE_LIMIT

      Rails.cache.write(key, current + 1, expires_in: 1.minute)
      true
    end
  end
end
