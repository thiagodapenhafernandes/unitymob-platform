# frozen_string_literal: true

require "json"
require "sinatra/base"

module Gateway
  class App < Sinatra::Base
    configure do
      set :show_exceptions, false
      set :raise_errors, false
      set :logging, true
    end

    before do
      content_type :json
    end

    get "/up" do
      status 200
      json(ok: true)
    end

    get "/webhooks/whatsapp" do
      halt 403, json(error: "invalid_verify_token") unless valid_verify_challenge?

      content_type :text
      status 200
      params.fetch("hub.challenge")
    end

    post "/webhooks/whatsapp" do
      raw_body = request.body.read
      signature = request.env["HTTP_X_HUB_SIGNATURE_256"].to_s

      unless MetaSignature.valid?(raw_body, signature, app_secret: meta_app_secret)
        halt 401, json(error: "invalid_signature")
      end

      payload = parse_json(raw_body)
      event_contexts = WhatsappPayload.extract_event_contexts(payload)
      events = event_contexts.map { |context| persist_event(context, payload, raw_body) }

      events.each { |event| forward_event(event, raw_body) }

      status 200
      json(ok: true, events: events.map { |event| event_response(event) })
    rescue JSON::ParserError
      status 400
      json(error: "invalid_json")
    end

    post "/internal/whatsapp/routes" do
      require_internal_token!

      attributes = route_attributes(parse_json(request.body.read))
      route = WebhookRoute.find_or_initialize_by(
        provider: attributes[:provider],
        phone_number_id: attributes[:phone_number_id]
      )
      route.assign_attributes(attributes)
      route.active = true if route.active.nil?
      route.save!

      status route.previously_new_record? ? 201 : 200
      json(route: route_payload(route))
    rescue ActiveRecord::RecordInvalid => error
      status 422
      json(error: "invalid_route", details: error.record.errors.full_messages)
    rescue JSON::ParserError
      status 400
      json(error: "invalid_json")
    end

    delete "/internal/whatsapp/routes/:phone_number_id" do
      require_internal_token!

      route = WebhookRoute.find_by(provider: "whatsapp", phone_number_id: params.fetch("phone_number_id"))
      halt 404, json(error: "route_not_found") unless route

      route.update!(active: false)
      json(route: route_payload(route))
    end

    error StandardError do
      env["sinatra.error"]&.then { |error| warn("#{error.class}: #{error.message}") }
      status 500
      json(error: "internal_error")
    end

    private

    def json(payload)
      JSON.generate(payload)
    end

    def parse_json(raw_body)
      JSON.parse(raw_body)
    end

    def valid_verify_challenge?
      params["hub.mode"] == "subscribe" &&
        params["hub.verify_token"].to_s == ENV.fetch("META_WEBHOOK_VERIFY_TOKEN", "")
    end

    def meta_app_secret
      ENV.fetch("META_APP_SECRET", ENV.fetch("FACEBOOK_APP_SECRET", ""))
    end

    def require_internal_token!
      token = ENV.fetch("INTERNAL_API_TOKEN", "")
      authorization = request.env["HTTP_AUTHORIZATION"].to_s
      return if !token.empty? && authorization == "Bearer #{token}"

      halt 401, json(error: "unauthorized")
    end

    def route_attributes(payload)
      {
        provider: "whatsapp",
        client_key: payload.fetch("client_key"),
        tenant_name: payload["tenant_name"],
        waba_id: payload["waba_id"].to_s,
        phone_number_id: payload.fetch("phone_number_id").to_s,
        target_url: payload.fetch("target_url"),
        forwarding_secret: payload.fetch("forwarding_secret"),
        active: payload.fetch("active", true)
      }
    end

    def persist_event(context, payload, raw_body)
      route = RouteResolver.call(phone_number_id: context[:phone_number_id], waba_id: context[:waba_id])

      WebhookEvent.create!(
        provider: "whatsapp",
        webhook_route: route,
        external_id: context[:external_id],
        event_type: context[:event_type],
        waba_id: context[:waba_id],
        phone_number_id: context[:phone_number_id],
        payload: payload,
        raw_body: raw_body,
        status: route ? "received" : "unrouted",
        received_at: Time.now
      )
    end

    def forward_event(event, raw_body)
      return unless event.webhook_route

      EventForwarder.call(event:, raw_body:)
    end

    def event_response(event)
      {
        id: event.id,
        external_id: event.external_id,
        status: event.status,
        route_id: event.webhook_route_id
      }
    end

    def route_payload(route)
      {
        id: route.id,
        client_key: route.client_key,
        tenant_name: route.tenant_name,
        waba_id: route.waba_id,
        phone_number_id: route.phone_number_id,
        target_url: route.target_url,
        active: route.active
      }
    end
  end
end
