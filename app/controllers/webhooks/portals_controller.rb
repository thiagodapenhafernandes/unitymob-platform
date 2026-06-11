module Webhooks
  class PortalsController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :load_layout_settings

    before_action :set_integration
    before_action :authenticate_signature!
    before_action :enforce_rate_limit!

    def events
      params_payload = request.request_parameters.presence
      payload =
        if params_payload.respond_to?(:to_unsafe_h)
          params_payload.to_unsafe_h
        elsif params_payload.is_a?(Hash)
          params_payload
        else
          parsed_body
        end
      parsed_events = Portal::WebhookParser.new(portal: @portal, payload: payload).events

      if parsed_events.blank?
        return render json: { error: "Payload inválido" }, status: :unprocessable_entity
      end

      now = Time.current

      parsed_events.each do |event|
        habitation = Habitation.find_by(codigo: event[:habitation_code]) if event[:habitation_code].present?

        PortalIntegrationEvent.create!(
          portal: @portal,
          habitation: habitation,
          habitation_code: event[:habitation_code],
          external_listing_id: event[:external_listing_id],
          event_type: event[:event_type],
          normalized_status: event[:normalized_status],
          received_at: now,
          source_ip: request.remote_ip,
          raw_payload: event[:raw_payload]
        )

        state = find_or_initialize_state(event)
        state.assign_attributes(
          habitation: habitation,
          habitation_code: event[:habitation_code],
          external_listing_id: event[:external_listing_id],
          last_event_type: event[:event_type],
          last_status: event[:normalized_status],
          last_received_at: now,
          last_payload: event[:raw_payload]
        )
        state.save!
      end

      @integration.update_columns(last_webhook_at: now, operational_status: "webhook_received", updated_at: now)

      render json: { ok: true, processed: parsed_events.size }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    private

    def set_integration
      @portal = params[:portal].to_s.downcase
      @integration = PortalIntegration.for_portal!(@portal)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Portal inválido" }, status: :not_found
    end

    def authenticate_signature!
      secret = @integration.webhook_secret.to_s
      signature = request.headers["X-Portal-Signature"].to_s
      raw_body = request.raw_post.to_s

      if secret.blank? || signature.blank?
        return render json: { error: "Assinatura ausente" }, status: :unauthorized
      end

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)
      unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        render json: { error: "Assinatura inválida" }, status: :unauthorized
      end
    end

    def parsed_body
      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      {}
    end

    def enforce_rate_limit!
      key = "portal_webhook_rate:#{request.remote_ip}:#{@portal}"
      current = Rails.cache.read(key).to_i
      limit = 120

      if current >= limit
        render json: { error: "Rate limit excedido" }, status: :too_many_requests
        return
      end

      Rails.cache.write(key, current + 1, expires_in: 1.minute)
    end

    def find_or_initialize_state(event)
      if event[:external_listing_id].present?
        PortalListingState.find_or_initialize_by(portal: @portal, external_listing_id: event[:external_listing_id])
      elsif event[:habitation_code].present?
        PortalListingState.find_or_initialize_by(portal: @portal, habitation_code: event[:habitation_code])
      else
        PortalListingState.new(portal: @portal)
      end
    end
  end
end
