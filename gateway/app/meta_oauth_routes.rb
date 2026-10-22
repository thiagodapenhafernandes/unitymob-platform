module Gateway
  module MetaOauthRoutes
    def self.registered(app)
      app.helpers do
        def meta_oauth_data
          request.body.rewind
          raw = request.body.read(4097)
          halt 413 if raw.bytesize > 4096
          data = JSON.parse(raw)
          halt 422 unless data.is_a?(Hash)
          data
        rescue JSON::ParserError
          halt 422
        end

        def meta_oauth_instance!
          id = request.env['HTTP_X_UNITYMOB_INSTANCE'].to_s
          config = MetaOauth.instance(id)
          token = request.env['HTTP_AUTHORIZATION'].to_s.delete_prefix('Bearer ')
          expected = config && config['token'].to_s
          halt 401 unless config && config['enabled'] == true && expected.length >= 32 && Rack::Utils.secure_compare(expected, token)
          [id, config]
        end
      end

      app.before do
        next unless request.path_info.start_with?('/oauth/meta/') ||
          ['/internal/meta/oauth_attempts', '/internal/meta/oauth_attempts/redeem'].include?(request.path_info)
        # Filter before Rack/Sinatra logging, including failures and cancellations.
        @meta_oauth_params = params.dup
        request.env['QUERY_STRING'] = '[FILTERED]' if request.query_string.present?
        request.env['REQUEST_URI'] = request.path_info
        headers 'Cache-Control' => 'no-store', 'Referrer-Policy' => 'no-referrer'
        halt 404 unless MetaOauth.enabled?
      end

      app.post '/internal/meta/oauth_attempts' do
        instance_id, config = meta_oauth_instance!
        data = meta_oauth_data
        tenant, user, nonce = data.values_at('tenant_id', 'user_id', 'nonce').map(&:to_s)
        halt 403 unless Array(config['tenant_ids']).map(&:to_s).include?(tenant)
        halt 422 unless user.match?(/\A[1-9]\d{0,18}\z/) && nonce.match?(/\A[0-9a-f]{64}\z/)
        Discovery.origin(config.fetch('origin'))
        halt 429 unless DiscoveryLimit.allow?("meta-start:#{instance_id}:#{tenant}:#{user}", limit: 10, period: 600)
        ticket = SecureRandom.hex(32)
        MetaOauthAttempt.create!(instance_id: instance_id, tenant_id: tenant, user_id: user, nonce_digest: MetaOauth.digest(nonce),
          start_digest: MetaOauth.digest(ticket), expires_at: Time.now + 600)
        json(start_url: "#{MetaOauth.origin}/oauth/meta/start?oauth_ticket=#{ticket}")
      rescue KeyError, ArgumentError, URI::InvalidURIError
        halt 422
      end

      app.get '/oauth/meta/start' do
        content_type :html
        ticket = @meta_oauth_params['oauth_ticket'].to_s
        halt 400 unless ticket.match?(/\A[0-9a-f]{64}\z/)
        attempt = MetaOauthAttempt.find_by(start_digest: MetaOauth.digest(ticket))
        halt 400 unless attempt
        state = SecureRandom.hex(32)
        session[:meta_oauth_browser] ||= SecureRandom.hex(32)
        attempt.with_lock do
          halt 410 if attempt.expires_at <= Time.now || attempt.started_at
          MetaOauth.return_url(attempt)
          attempt.update!(started_at: Time.now, state_digest: MetaOauth.digest(state), browser_digest: MetaOauth.digest(session[:meta_oauth_browser]))
        end
        redirect MetaOauth.authorization_url(state), 302
      rescue MetaOauth::Unavailable
        halt 403
      end

      app.get '/oauth/meta/callback' do
        content_type :html
        state = @meta_oauth_params['state'].to_s
        halt 400 unless state.match?(/\A[0-9a-f]{64}\z/)
        attempt = MetaOauthAttempt.find_by(state_digest: MetaOauth.digest(state))
        halt 400 unless attempt && attempt.browser_digest == MetaOauth.digest(session[:meta_oauth_browser])
        destination = MetaOauth.return_url(attempt)
        attempt.with_lock do
          halt 410 if attempt.expires_at <= Time.now || attempt.callback_at
          attempt.update!(callback_at: Time.now)
        end
        result = if @meta_oauth_params['error'].present?
          { 'error' => 'authorization_declined' }
        else
          code = @meta_oauth_params['code'].to_s
          halt 400 unless code.length.between?(1, 4096)
          MetaOauth.exchange(code)
        end
        handoff = SecureRandom.hex(32)
        attempt.update!(handoff_digest: MetaOauth.digest(handoff), encrypted_result: MetaOauth.cipher.encrypt_and_sign(result))
        redirect "#{destination}?#{URI.encode_www_form(oauth_handoff: handoff)}", 302
      rescue MetaOauth::Unavailable, ActiveSupport::MessageEncryptor::InvalidMessage
        attempt&.update!(failure: 'authorization_unavailable')
        halt 502, 'Conexão indisponível. Volte ao CRM e tente novamente.'
      end

      app.post '/internal/meta/oauth_attempts/redeem' do
        instance_id, config = meta_oauth_instance!
        data = meta_oauth_data
        handoff = data['handoff'].to_s
        halt 400 unless handoff.match?(/\A[0-9a-f]{64}\z/)
        attempt = MetaOauthAttempt.find_by(handoff_digest: MetaOauth.digest(handoff), instance_id: instance_id)
        halt 403 unless attempt && Array(config['tenant_ids']).map(&:to_s).include?(attempt.tenant_id) &&
          data['tenant_id'].to_s == attempt.tenant_id && data['user_id'].to_s == attempt.user_id &&
          Rack::Utils.secure_compare(MetaOauth.digest(data['nonce']), attempt.nonce_digest)
        result = nil
        attempt.with_lock do
          halt 410 if attempt.expires_at <= Time.now || attempt.consumed_at
          result = MetaOauth.cipher.decrypt_and_verify(attempt.encrypted_result)
          attempt.update!(consumed_at: Time.now, encrypted_result: nil)
        end
        json(result)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        halt 410
      end
    end
  end
end
