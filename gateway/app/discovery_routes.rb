module Gateway
  module DiscoveryRoutes
    def self.registered(app)
      app.helpers do
        def discovery_payload
          raw = request.body.read(4097)
          halt 413, json(error: 'invalid_request') if raw.bytesize > 4096
          data = JSON.parse(raw)
          halt 422, json(error: 'invalid_request') unless data.is_a?(Hash)
          data
        end
      end
      app.before '/discovery/v2/*' do
        headers 'Cache-Control' => 'no-store'
        allow_discovery_cors!
        halt 413, json(error: 'invalid_request') if request.content_length.to_i > 4096
      end
      app.options('/discovery/v2/*') { status 204; '' }

      app.post '/internal/discovery/v2/memberships' do
        halt 413 unless request.content_length.to_i <= 4096
        instance_id = request.env['HTTP_X_UNITYMOB_INSTANCE'].to_s
        config = Discovery.instance(instance_id)
        actual = request.env['HTTP_AUTHORIZATION'].to_s.delete_prefix('Bearer ')
        expected = config && config['token'].to_s
        halt 401 unless expected && expected.length >= 32 && Rack::Utils.secure_compare(expected, actual)
        Discovery.origin(config.fetch('origin'))
        data = discovery_payload
        tenant_id, user_id = data.values_at('tenant_id', 'user_id').map(&:to_s)
        halt 403 unless config.fetch('tenant_ids', []).map(&:to_s).include?(tenant_id)
        halt 422 unless user_id.match?(/\A[1-9]\d{0,18}\z/) && [true, false].include?(data['active'])
        timestamp = Time.iso8601(data.fetch('source_updated_at'))
        halt 422 if timestamp > Time.now.utc + 300
        attrs = {email: Discovery.email(data['email']), tenant_name: data.fetch('tenant_name').to_s.first(200), active: data['active'], source_updated_at: timestamp}
        row = AccountMembership.create_or_find_by!(instance_id: instance_id, tenant_id: tenant_id, user_id: user_id) { |record| record.assign_attributes(attrs) }
        row.with_lock { row.update!(attrs) if timestamp > row.source_updated_at }
        json(ok: true)
      rescue ArgumentError, KeyError, JSON::ParserError, ActiveRecord::RecordInvalid
        halt 422, json(error: 'invalid_request')
      end

      app.post '/discovery/v2/challenges' do
        halt 429, json(error: 'rate_limited') unless DiscoveryLimit.allow?("start-ip:#{request.ip}", limit: 10, period: 600)
        data = discovery_payload
        address = Discovery.email(data['email'])
        halt 429, json(error: 'rate_limited') unless DiscoveryLimit.allow?("start-email:#{address}", limit: 3, period: 600)
        token, code = SecureRandom.urlsafe_base64(32), format('%06d', SecureRandom.random_number(1_000_000))
        row = DiscoveryChallenge.create!(token_digest: Discovery.digest(token), email: address,
          code_digest: Discovery.digest("#{token}:#{code}"), expires_at: Time.now.utc + 600)
        # Same response and delivery for known and unknown addresses: no public account enumeration.
        Discovery.send_code(address, code)
        status 202
        json(challenge: token, expires_in: 600)
      rescue ArgumentError, JSON::ParserError
        halt 422, json(error: 'invalid_request')
      rescue StandardError
        row&.destroy!
        halt 503, json(error: 'discovery_unavailable')
      end

      app.post '/discovery/v2/verify' do
        halt 429, json(error: 'rate_limited') unless DiscoveryLimit.allow?("verify-ip:#{request.ip}", limit: 30, period: 600)
        data = discovery_payload
        token = data['challenge'].to_s
        halt 422 unless token.match?(/\A[A-Za-z0-9_-]{43}\z/)
        row = DiscoveryChallenge.find_by(token_digest: Discovery.digest(token))
        halt 422, json(error: 'invalid_code') unless row
        accounts = nil
        row.with_lock do
          halt 422, json(error: 'invalid_code') if row.consumed_at || row.expires_at <= Time.now.utc || row.attempts >= 5
          row.update!(attempts: row.attempts + 1)
          if Rack::Utils.secure_compare(row.code_digest, Discovery.digest("#{token}:#{data['code']}"))
            row.update!(consumed_at: Time.now.utc)
            accounts = AccountMembership.where(email: row.email, active: true).order(:tenant_name, :id).limit(50).filter_map(&:public_account)
          end
        end
        halt 422, json(error: 'invalid_code') unless accounts
        json(email: row.email, accounts: accounts, expires_at: (Time.now.utc + 600).iso8601)
      rescue ArgumentError, KeyError, JSON::ParserError
        halt 422, json(error: 'invalid_request')
      end
    end
  end
end
