# frozen_string_literal: true

require "digest"

module Gateway
  module TiktokRoutes
    def self.registered(app)
      app.post "/internal/tiktok/oauth_states" do
        require_internal_token!
        data = parse_json(request.body.read)
        halt 422, json(error: "invalid_oauth_state") unless data.is_a?(Hash)
        target = URI.parse(data["return_url"].to_s)
        unless data["state"].to_s.match?(/\A[0-9a-f]{64}\z/) && target.scheme == "https" && target.host.present? &&
            target.userinfo.nil? && target.query.nil? && target.fragment.nil? && target.path == "/admin/tiktok_integration/callback"
          halt 422, json(error: "invalid_oauth_state")
        end
        TiktokOauthState.where("expires_at < ?", Time.now).delete_all
        TiktokOauthState.create!(state_digest: Digest::SHA256.hexdigest(data.fetch("state")), return_url: target.to_s, expires_at: Time.now + 600)
        json(ok: true)
      rescue JSON::ParserError, URI::InvalidURIError, ActiveRecord::RecordNotUnique
        halt 422, json(error: "invalid_oauth_state")
      end

      app.get "/oauth/tiktok/callback" do
        state = params["state"].to_s
        code = params["auth_code"].to_s
        request.env["QUERY_STRING"] = "[FILTERED]"
        request.env["REQUEST_URI"] = "/oauth/tiktok/callback?[FILTERED]"
        halt 400, json(error: "invalid_oauth_state") unless state.match?(/\A[0-9a-f]{64}\z/)
        oauth = TiktokOauthState.find_by(state_digest: Digest::SHA256.hexdigest(state))
        halt 400, json(error: "invalid_oauth_state") unless oauth
        destination = nil
        oauth.with_lock do
          halt 400, json(error: "expired_oauth_state") if oauth.expires_at <= Time.now
          destination = URI(oauth.return_url)
          destination.query = URI.encode_www_form(state: state, auth_code: code)
          oauth.destroy!
        end
        headers "Referrer-Policy" => "no-referrer", "Cache-Control" => "no-store"
        redirect destination.to_s, 302
      rescue ActiveRecord::RecordNotFound
        halt 400, json(error: "invalid_oauth_state")
      end

      app.post "/internal/tiktok/routes" do
        require_internal_token!
        data = parse_json(request.body.read)
        halt 422, json(error: "invalid_route") unless data.is_a?(Hash)
        key = data["client_key"].to_s
        advertiser_id = data["advertiser_id"].to_s
        target = URI.parse(data["target_url"].to_s)
        unless key.match?(/\A[0-9a-f-]{36}\z/) && advertiser_id.match?(/\A\d+\z/) &&
            target.scheme == "https" && target.host.present? && target.userinfo.nil? && target.query.nil? && target.fragment.nil? &&
            target.path == "/webhooks/tiktok/#{key}" && data["forwarding_secret"].to_s.length >= 20 && [true, false].include?(data["active"])
          halt 422, json(error: "invalid_route")
        end
        route = WebhookRoute.create_or_find_by!(provider: "tiktok", advertiser_id: advertiser_id) do |record|
          record.assign_attributes(data.slice("client_key", "target_url", "tenant_name", "forwarding_secret", "active"))
        end
        route.with_lock do
          halt 409, json(error: "advertiser_destination_conflict") unless route.client_key == key
          route.update!(data.slice("target_url", "tenant_name", "forwarding_secret", "active"))
          if route.active?
            WebhookEvent.where(provider: "tiktok", advertiser_id: advertiser_id, status: "unrouted")
              .update_all(webhook_route_id: route.id, status: "received")
          end
        end
        json(ok: true)
      rescue JSON::ParserError, URI::InvalidURIError
        halt 422, json(error: "invalid_route")
      end

      app.post "/internal/tiktok/connections/:key" do
        require_internal_token!
        data = parse_json(request.body.read)
        halt 422, json(error: "invalid_selection") unless data.is_a?(Hash) && data["advertiser_ids"].is_a?(Array)
        WebhookRoute.where(provider: "tiktok", client_key: params[:key]).where.not(advertiser_id: data["advertiser_ids"].map(&:to_s)).update_all(active: false)
        json(ok: true)
      rescue JSON::ParserError
        halt 422, json(error: "invalid_selection")
      end

      app.post "/webhooks/tiktok" do
        # Marketing API Subscription docs do not specify TikTok-Signature (a different product).
        # Authenticate the configured callback with a 256-bit bearer token over HTTPS.
        provided = params["webhook_token"].to_s
        request.env["QUERY_STRING"] = "webhook_token=[FILTERED]"
        request.env["REQUEST_URI"] = "/webhooks/tiktok?webhook_token=[FILTERED]"
        secret = ENV["TIKTOK_WEBHOOK_TOKEN"].to_s
        unless secret.match?(/\A[0-9a-f]{64}\z/) && Rack::Utils.secure_compare(secret, provided)
          halt 401, json(error: "invalid_authentication")
        end
        payload = parse_json(request.body.read)
        unless payload.is_a?(Hash) && payload["object"] == 1 && payload["entry"].is_a?(Array) && payload["entry"].any? &&
            payload["entry"].all? { |entry| entry.is_a?(Hash) && entry["id"].to_s.present? && entry["advertiser_id"].to_s.match?(/\A\d+\z/) &&
              entry["page_id"].to_s.present? && entry["lead_source"].to_s.in?(["", "INSTANT_FORM"]) &&
              entry["changes"].is_a?(Array) && entry["changes"].all? { |field| field.is_a?(Hash) && field["field"].is_a?(String) && field.key?("value") } }
          halt 422, json(error: "invalid_lead")
        end
        connection_key = params["connection_key"].to_s
        routes = WebhookRoute.where(provider: "tiktok", client_key: connection_key, active: true).index_by(&:advertiser_id)
        halt 409, json(error: "unknown_advertiser") unless payload["entry"].all? { |entry| routes.key?(entry["advertiser_id"].to_s) }
        payload["entry"].each do |entry|
          route = routes.fetch(entry["advertiser_id"].to_s)
          event = WebhookEvent.create_or_find_by!(provider: "tiktok", advertiser_id: entry["advertiser_id"].to_s, external_id: entry["id"].to_s) do |record|
            record.assign_attributes(webhook_route: route, form_id: entry["page_id"].to_s, event_type: "lead", payload: entry,
              raw_body: JSON.generate(entry), received_at: Time.now, status: route ? "received" : "unrouted")
          end
          event.with_lock { forward_event(event, event.raw_body) if event.status == "received" }
        end
        json(ok: true)
      rescue JSON::ParserError
        halt 400, json(error: "invalid_json")
      end
    end
  end
end
