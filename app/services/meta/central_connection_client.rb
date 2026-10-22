module Meta
  class CentralConnectionClient
    class Error < StandardError; end

    def self.enabled_for?(tenant)
      ENV['META_CENTRAL_CONNECT_ENABLED'] == 'true' &&
        ENV.fetch('META_CENTRAL_CONNECT_TENANT_IDS', '').split(',').map(&:strip).include?(tenant.id.to_s)
    end

    def initialize(tenant:, user:)
      @tenant, @user = tenant, user
    end

    def origin
      uri = URI.parse(ENV.fetch('APP_HOST'))
      raise Error unless uri.scheme == 'https' && uri.host.present? && uri.port == 443 &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && ['', '/'].include?(uri.path)
      "https://#{uri.host}"
    rescue KeyError, URI::InvalidURIError
      raise Error
    end

    def gateway
      uri = URI.parse(ENV.fetch('META_CENTRAL_CONNECT_URL', 'https://webhooks.unitymob.com.br'))
      raise Error unless uri.scheme == 'https' && uri.host.present? && uri.port == 443 &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && ['', '/'].include?(uri.path)
      "https://#{uri.host}"
    rescue URI::InvalidURIError
      raise Error
    end

    def register(nonce:)
      result = post('/internal/meta/oauth_attempts', nonce: nonce)
      uri = URI.parse(result.fetch('start_url'))
      expected = URI(gateway)
      query = URI.decode_www_form(uri.query.to_s).to_h
      raise Error unless uri.scheme == expected.scheme && uri.host == expected.host && uri.port == expected.port &&
        uri.userinfo.nil? && uri.fragment.nil? && uri.path == '/oauth/meta/start' && query.keys == ['oauth_ticket'] && query['oauth_ticket'].match?(/\A[0-9a-f]{64}\z/)
      uri.to_s
    rescue KeyError, URI::InvalidURIError, ArgumentError, TypeError
      raise Error
    end

    def redeem(handoff:, nonce:)
      result = post('/internal/meta/oauth_attempts/redeem', handoff: handoff, nonce: nonce)
      raise Error if result['error'].present?
      raise Error unless ENV['FACEBOOK_APP_ID'].present? && result['app_id'] == ENV['FACEBOOK_APP_ID'] &&
        result['access_token'].is_a?(String) && result['access_token'].length.between?(1, 8192) &&
        result['facebook_user_id'].to_s.match?(/\A\d+\z/) && result['granted_permissions'].is_a?(Array)
      result
    end

    private

    def post(path, attributes)
      raise Error unless self.class.enabled_for?(@tenant) && @user.tenant_id == @tenant.id
      token = ENV.fetch('META_CENTRAL_CONNECT_TOKEN')
      raise Error if token.length < 32
      response = HTTParty.post("#{gateway}#{path}", timeout: 15, follow_redirects: false,
        headers: { 'Authorization' => "Bearer #{token}", 'X-Unitymob-Instance' => ENV.fetch('META_CENTRAL_CONNECT_INSTANCE'), 'Content-Type' => 'application/json' },
        body: attributes.merge(tenant_id: @tenant.id.to_s, user_id: @user.id.to_s).to_json)
      raise Error unless response.success? && response.body.is_a?(String) && response.body.bytesize <= 16384
      data = JSON.parse(response.body)
      raise Error unless data.is_a?(Hash)
      data
    rescue KeyError, JSON::ParserError, TypeError, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, HTTParty::Error
      raise Error
    end
  end
end
