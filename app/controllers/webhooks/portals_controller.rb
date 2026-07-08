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
        # Habitation resolvida SEMPRE pelo tenant DESTA integração — nunca por
        # um tenant público genérico (que cruzaria contas).
        habitation = webhook_tenant&.habitations&.find_by(codigo: event[:habitation_code]) if event[:habitation_code].present?

        PortalIntegrationEvent.create!(
          event_attributes(
            habitation: habitation,
            habitation_code: event[:habitation_code],
            external_listing_id: event[:external_listing_id],
            event_type: event[:event_type],
            normalized_status: event[:normalized_status],
            received_at: now,
            source_ip: request.remote_ip,
            raw_payload: event[:raw_payload]
          )
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
        assign_tenant(state)
        state.save!
      end

      @integration.update_columns(last_webhook_at: now, operational_status: "webhook_received", updated_at: now)

      render json: { ok: true, processed: parsed_events.size }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    private

    # A rota /portals/:portal/events não carrega token, e pós-migration o
    # portal deixa de ser único global (unique = tenant_id + portal). O tenant
    # é então resolvido pela ASSINATURA HMAC: entre as integrações daquele
    # portal, a que valida a assinatura do corpo identifica o tenant dono.
    def set_integration
      @portal = params[:portal].to_s.downcase

      unless PortalIntegration::PORTALS.include?(@portal)
        return render json: { error: "Portal inválido" }, status: :not_found
      end

      @candidate_integrations = PortalIntegration.where(portal: @portal).to_a

      if @candidate_integrations.empty?
        render json: { error: "Portal inválido" }, status: :not_found
      end
    end

    def authenticate_signature!
      signature = request.headers["X-Portal-Signature"].to_s
      raw_body = request.raw_post.to_s

      if signature.blank?
        return render json: { error: "Assinatura ausente" }, status: :unauthorized
      end

      @integration = @candidate_integrations.find do |integration|
        secret = integration.webhook_secret.to_s
        next false if secret.blank?

        expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)
        ActiveSupport::SecurityUtils.secure_compare(signature, expected)
      end

      if @integration.nil?
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

    # Estado localizado/criado DENTRO do tenant desta integração — evita casar
    # o estado de outra conta que use o mesmo portal e external_listing_id.
    def find_or_initialize_state(event)
      scope = scoped_states_relation

      if event[:external_listing_id].present?
        scope.find_or_initialize_by(portal: @portal, external_listing_id: event[:external_listing_id])
      elsif event[:habitation_code].present?
        scope.find_or_initialize_by(portal: @portal, habitation_code: event[:habitation_code])
      else
        scope.new(portal: @portal)
      end
    end

    def scoped_states_relation
      if PortalListingState.column_names.include?("tenant_id") && webhook_tenant.present?
        PortalListingState.where(tenant: webhook_tenant)
      else
        PortalListingState.all
      end
    end

    # Tenant dono da integração resolvida pela assinatura. Tolerante
    # pré-migration (integração sem coluna tenant_id retorna nil).
    def webhook_tenant
      return @webhook_tenant if defined?(@webhook_tenant)

      @webhook_tenant =
        if @integration.respond_to?(:tenant) && @integration.has_attribute?(:tenant_id)
          @integration.tenant
        end
    end

    # Injeta tenant_id nos eventos/estados quando a coluna existe.
    def event_attributes(attrs)
      attrs = attrs.merge(portal: @portal)
      attrs[:tenant] = webhook_tenant if PortalIntegrationEvent.column_names.include?("tenant_id") && webhook_tenant.present?
      attrs
    end

    def assign_tenant(state)
      return unless PortalListingState.column_names.include?("tenant_id")
      return if webhook_tenant.blank?

      state.tenant = webhook_tenant
    end
  end
end
