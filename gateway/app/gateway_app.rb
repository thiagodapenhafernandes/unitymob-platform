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

    get "/webhooks/meta" do
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

      alert_unrouted_events(events)
      events.each { |event| forward_event(event, raw_body) }

      status 200
      json(ok: true, events: events.map { |event| event_response(event) })
    rescue JSON::ParserError
      status 400
      json(error: "invalid_json")
    end

    post "/webhooks/meta" do
      raw_body = request.body.read
      signature = request.env["HTTP_X_HUB_SIGNATURE_256"].to_s

      unless MetaSignature.valid?(raw_body, signature, app_secret: meta_app_secret)
        halt 401, json(error: "invalid_signature")
      end

      payload = parse_json(raw_body)
      event_contexts = MetaLeadPayload.extract_event_contexts(payload)
      events = event_contexts.map { |context| persist_meta_event(context, payload, raw_body) }

      alert_unrouted_events(events)
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

    post "/internal/meta/routes" do
      require_internal_token!

      attributes = meta_route_attributes(parse_json(request.body.read))
      route = WebhookRoute.find_or_initialize_by(
        provider: attributes[:provider],
        page_id: attributes[:page_id],
        form_id: attributes[:form_id].presence
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

    delete "/internal/meta/routes/:page_id" do
      require_internal_token!

      route = WebhookRoute.find_by(provider: "meta", page_id: params.fetch("page_id"), form_id: [nil, ""])
      halt 404, json(error: "route_not_found") unless route

      route.update!(active: false)
      json(route: route_payload(route))
    end

    post "/internal/account_routes" do
      require_internal_token!

      attributes = account_route_attributes(parse_json(request.body.read))
      route = AccountRoute.find_or_initialize_by(email: attributes[:email])
      route.assign_attributes(attributes)
      route.active = true if route.active.nil?
      route.save!

      status route.previously_new_record? ? 201 : 200
      json(account_route: account_route_payload(route))
    rescue ActiveRecord::RecordInvalid => error
      status 422
      json(error: "invalid_account_route", details: error.record.errors.full_messages)
    rescue JSON::ParserError
      status 400
      json(error: "invalid_json")
    end

    delete "/internal/account_routes/:email" do
      require_internal_token!

      route = AccountRoute.find_by(email: params.fetch("email").to_s.strip.downcase)
      halt 404, json(error: "account_route_not_found") unless route

      route.update!(active: false)
      json(account_route: account_route_payload(route))
    end

    # Único endpoint público chamado via fetch() de dentro do app mobile (outra
    # origem: capacitor://localhost / http://localhost), por isso precisa de
    # CORS — os demais endpoints são servidor-a-servidor (webhooks, /internal)
    # e não passam por navegador, então não precisam disso.
    options "/discovery/resolve" do
      allow_discovery_cors!
      status 204
      ""
    end

    post "/discovery/resolve" do
      allow_discovery_cors!
      payload = parse_json(request.body.read)
      route = AccountResolver.call(email: payload["email"])
      halt 404, json(error: "account_not_found") unless route

      json(tenant_url: route.target_url)
    rescue JSON::ParserError
      status 400
      json(error: "invalid_json")
    end

    get "/internal/webhook_events" do
      require_internal_token!

      events = filtered_events.limit(events_limit)
      json(
        events: events.map { |event| event_payload(event) },
        count: events.size
      )
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

    def allow_discovery_cors!
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
      response.headers["Access-Control-Allow-Headers"] = "Content-Type"
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

    def account_route_attributes(payload)
      {
        email: payload.fetch("email").to_s.strip.downcase,
        tenant_name: payload["tenant_name"],
        target_url: payload.fetch("target_url"),
        active: payload.fetch("active", true)
      }
    end

    def account_route_payload(route)
      {
        id: route.id,
        email: route.email,
        tenant_name: route.tenant_name,
        target_url: route.target_url,
        active: route.active
      }
    end

    def meta_route_attributes(payload)
      {
        provider: "meta",
        client_key: payload.fetch("client_key"),
        tenant_name: payload["tenant_name"],
        page_id: payload.fetch("page_id").to_s,
        form_id: payload["form_id"].to_s.strip.empty? ? nil : payload["form_id"].to_s,
        target_url: payload.fetch("target_url"),
        forwarding_secret: payload.fetch("forwarding_secret"),
        active: payload.fetch("active", true)
      }
    end

    def persist_event(context, payload, raw_body)
      route = RouteResolver.whatsapp(phone_number_id: context[:phone_number_id], waba_id: context[:waba_id])

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

    def persist_meta_event(context, payload, raw_body)
      route = RouteResolver.meta(page_id: context[:page_id], form_id: context[:form_id])

      WebhookEvent.create!(
        provider: "meta",
        webhook_route: route,
        external_id: context[:external_id],
        event_type: context[:event_type],
        page_id: context[:page_id],
        form_id: context[:form_id],
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

    def alert_unrouted_events(events)
      events.select { |event| event.status == "unrouted" }.each do |event|
        UnroutedEventAlerter.call(event)
      end
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
        page_id: route.page_id,
        form_id: route.form_id,
        target_url: route.target_url,
        active: route.active
      }
    end

    def filtered_events
      scope = WebhookEvent.order(received_at: :desc, id: :desc)
      scope = scope.where(provider: params["provider"].to_s) if params["provider"].to_s.strip != ""
      scope = scope.where(status: params["status"].to_s) if params["status"].to_s.strip != ""
      scope = scope.where(page_id: params["page_id"].to_s) if params["page_id"].to_s.strip != ""
      scope = scope.where(form_id: params["form_id"].to_s) if params["form_id"].to_s.strip != ""
      scope = scope.where(phone_number_id: params["phone_number_id"].to_s) if params["phone_number_id"].to_s.strip != ""
      scope
    end

    def events_limit
      [[params.fetch("limit", 50).to_i, 1].max, 200].min
    end

    def event_payload(event)
      {
        id: event.id,
        provider: event.provider,
        status: event.status,
        event_type: event.event_type,
        external_id: event.external_id,
        route_id: event.webhook_route_id,
        waba_id: event.waba_id,
        phone_number_id: event.phone_number_id,
        page_id: event.page_id,
        form_id: event.form_id,
        attempts: event.attempts,
        last_error: event.last_error,
        received_at: event.received_at&.iso8601,
        forwarded_at: event.forwarded_at&.iso8601,
        next_retry_at: event.next_retry_at&.iso8601
      }
    end
  end
end
