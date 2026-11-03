module Gateway
  module ImovelwebRoutes
    def self.registered(app)
      app.post '/internal/imovelweb/routes' do
        require_internal_token!
        data = parse_json(request.body.read)
        halt 422, json(error: 'invalid_route') unless data.is_a?(Hash)
        key = data['client_key'].to_s
        code = data['client_code'].to_s
        target = URI.parse(data['target_url'].to_s)
        unless key.match?(/\A[0-9a-f-]{36}\z/) && code.match?(/\A[A-Za-z0-9_.@-]{1,255}\z/) &&
            %w[sandbox production].include?(data['environment']) && target.scheme == 'https' && target.host.present? &&
            target.path == "/webhooks/imovelweb/#{key}" && target.query.nil? && target.fragment.nil? && target.userinfo.nil? &&
            data['forwarding_secret'].is_a?(String) && data['forwarding_secret'].length >= 32 && [true, false].include?(data['active'])
          halt 422, json(error: 'invalid_route')
        end
        route = WebhookRoute.find_or_initialize_by(provider: 'imovelweb', client_key: key)
        if route.persisted? && [route.imovelweb_client_code, route.imovelweb_environment] != [code, data['environment']]
          halt 409, json(error: 'immutable_route_identity')
        end
        route.assign_attributes(imovelweb_client_code: code, imovelweb_environment: data['environment'],
          target_url: target.to_s, forwarding_secret: data['forwarding_secret'], active: data['active'])
        route.save!
        json(ok: true)
      rescue JSON::ParserError, URI::InvalidURIError
        halt 422, json(error: 'invalid_route')
      rescue ActiveRecord::RecordNotUnique
        halt 409, json(error: 'client_already_linked')
      end

      app.post '/webhooks/imovelweb/:environment' do
        halt 503, json(error: 'receiving_disabled') unless ENV['IMOVELWEB_RECEIVING_ENABLED'] == 'true' && QueuedDelivery.enabled?
        environment = params[:environment]
        halt 404 unless %w[sandbox production].include?(environment)
        secret = ENV["IMOVELWEB_#{environment.upcase}_CALLBACK_TOKEN"].to_s
        provided = request.env['HTTP_AUTHORIZATION'].to_s
        halt 401 unless secret.length >= 32 && Rack::Utils.secure_compare("Bearer #{secret}", provided)
        halt 413 if request.content_length.to_i > 65_536
        raw = request.body.read(65_537)
        halt 413 if raw.bytesize > 65_536
        entry = ImovelwebPayload.normalize(JSON.parse(raw)).merge('environment' => environment)
        route = WebhookRoute.find_by(provider: 'imovelweb', imovelweb_environment: environment,
          imovelweb_client_code: entry.fetch('client_code'), active: true)
        halt 404, json(error: 'unknown_client') unless route
        # Durable receipt only: no network call on the portal's 1.5-second deadline.
        QueuedDelivery.persist(provider: 'imovelweb', webhook_route: route, external_id: entry.fetch('event_id'),
          event_type: entry.fetch('event_type'), payload: entry, raw_body: JSON.generate(entry), received_at: Time.now, status: 'received')
        status 202
        json(ok: true)
      rescue JSON::ParserError, ImovelwebPayload::Invalid
        halt 422, json(error: 'invalid_callback')
      end
    end
  end
end
