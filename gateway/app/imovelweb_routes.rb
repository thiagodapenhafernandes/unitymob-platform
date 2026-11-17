module Gateway
  module ImovelwebRoutes
    def self.authentication_failure(secret:, header:)
      return 'not_configured' if secret.length < 32
      return 'missing' if header.empty?
      # O esquema HTTP é case-insensitive; o token continua exato e case-sensitive.
      match = header.match(/\A[ \t]*Bearer[ \t]+([^ \t\r\n]+)[ \t]*\z/i)
      return 'invalid_scheme' unless match
      'token_mismatch' unless Rack::Utils.secure_compare(secret, match[1])
    end

    def self.registered(app)
      app.post '/internal/imovelweb/authorization' do
        require_internal_token!
        data = parse_json(request.body.read)
        halt 422, json(error: 'invalid_request') unless data.is_a?(Hash) &&
          %w[sandbox production].include?(data['environment']) && data['client_code'].to_s.match?(/\A[A-Za-z0-9_.@-]{1,255}\z/)
        client = ImovelwebClient.new(environment: data['environment'])
        json(script_url: client.authorization_script(client_code: data['client_code']))
      rescue ImovelwebClient::Error, KeyError
        halt 503, json(error: 'authorization_unavailable')
      end

      app.post '/internal/imovelweb/verification' do
        require_internal_token!
        data = parse_json(request.body.read)
        halt 422, json(error: 'invalid_request') unless data.is_a?(Hash) &&
          %w[sandbox production].include?(data['environment']) && data['client_code'].to_s.match?(/\A[A-Za-z0-9_.@-]{1,255}\z/)
        advertiser = ImovelwebClient.new(environment: data['environment']).authorized_advertiser(client_code: data['client_code'])
        json(confirmed: advertiser.present?, advertiser_code: advertiser&.fetch(:advertiser_code))
      rescue ImovelwebClient::Error, KeyError
        halt 503, json(error: 'verification_unavailable')
      end

      app.post '/internal/imovelweb/listings' do
        require_internal_token!
        data = parse_json(request.body.read)
        halt 422, json(error: 'invalid_request') unless data.is_a?(Hash) && data['page'].is_a?(Integer) && data['page'].between?(0, 999) &&
          data['client_key'].to_s.match?(/\A[0-9a-f-]{36}\z/) && data['client_code'].to_s.match?(/\A[A-Za-z0-9_.@-]{1,255}\z/) &&
          %w[sandbox production].include?(data['environment'])
        route = WebhookRoute.find_by(provider: 'imovelweb', client_key: data['client_key'],
          imovelweb_client_code: data['client_code'], imovelweb_environment: data['environment'], active: true)
        halt 404, json(error: 'unknown_client') unless route
        client = ImovelwebClient.new(environment: route.imovelweb_environment)
        json(client.associate_online_listings(client_code: route.imovelweb_client_code, page: data['page']))
      rescue ImovelwebClient::Error, KeyError
        halt 503, json(error: 'listing_association_unavailable')
      end

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
        if data['advertiser_code'].present? || (data['active'] && code.match?(/\A(?:um|pending)-/))
          advertiser = ImovelwebClient.new(environment: data['environment']).authorized_advertiser(client_code: code)
          halt 409, json(error: 'authorization_pending') unless advertiser && advertiser[:advertiser_code] == data['advertiser_code']
          # Older routes used the numeric branch code before self-service Login existed.
          others = WebhookRoute.where(provider: 'imovelweb', imovelweb_environment: data['environment']).where.not(client_key: key)
          if others.where(imovelweb_client_code: advertiser[:advertiser_code]).exists? ||
              others.where(imovelweb_advertiser_code: advertiser[:advertiser_code]).exists?
            halt 409, json(error: 'advertiser_already_linked')
          end
          route.imovelweb_advertiser_code = advertiser[:advertiser_code]
        end
        route.assign_attributes(imovelweb_client_code: code, imovelweb_environment: data['environment'],
          target_url: target.to_s, forwarding_secret: data['forwarding_secret'], active: data['active'])
        route.save!
        json(ok: true)
      rescue ImovelwebClient::Error, KeyError
        halt 503, json(error: 'verification_unavailable')
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
        failure = ImovelwebRoutes.authentication_failure(secret: secret, header: provided)
        if failure
          warn({ provider: 'imovelweb', event: 'callback_auth_rejected', environment: environment, reason: failure }.to_json)
          headers 'WWW-Authenticate' => 'Bearer realm="Unitymob Imovelweb"'
          halt 401
        end
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
