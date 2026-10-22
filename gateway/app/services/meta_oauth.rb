require 'active_support/message_encryptor'
require 'net/http'
require 'digest'

module Gateway
  module MetaOauth
    class Unavailable < StandardError; end
    SCOPES = %w[email pages_show_list pages_read_engagement pages_manage_ads pages_manage_metadata ads_management leads_retrieval business_management].freeze
    module_function

    def origin
      Discovery.origin(ENV.fetch('META_OAUTH_PUBLIC_ORIGIN'))
    end

    def enabled?
      ENV['META_OAUTH_ENABLED'] == 'true' && ENV['META_OAUTH_APP_ID'] == '1766223014200910' &&
        ENV['DISCOVERY_SECRET'].to_s.length >= 32 && ENV['META_APP_SECRET'].to_s != '' && ENV['META_OAUTH_ENCRYPTION_KEY'].to_s.match?(/\A[0-9a-f]{64}\z/) && origin.present?
    rescue KeyError, ArgumentError, URI::InvalidURIError
      false
    end

    def instance(id)
      instances = JSON.parse(ENV.fetch('META_OAUTH_INSTANCES', '{}'))
      config = instances[id] if instances.is_a?(Hash)
      config if config.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def digest(value)
      Digest::SHA256.hexdigest(value.to_s)
    end

    def cipher
      ActiveSupport::MessageEncryptor.new([ENV.fetch('META_OAUTH_ENCRYPTION_KEY')].pack('H*'), cipher: 'aes-256-gcm', serializer: JSON)
    end

    def callback_url
      "#{origin}/oauth/meta/callback"
    end

    def return_url(attempt)
      config = instance(attempt.instance_id)
      raise Unavailable unless config && config['enabled'] == true && Array(config['tenant_ids']).map(&:to_s).include?(attempt.tenant_id)
      "#{Discovery.origin(config.fetch('origin'))}/admin/meta_connection"
    end

    def authorization_url(state)
      "https://www.facebook.com/v24.0/dialog/oauth?#{URI.encode_www_form(client_id: ENV.fetch('META_OAUTH_APP_ID'), redirect_uri: callback_url, state: state, scope: SCOPES.join(','), response_type: 'code', auth_type: 'rerequest')}"
    end

    def graph(path, params)
      uri = URI("https://graph.facebook.com/v24.0/#{path}")
      uri.query = URI.encode_www_form(params)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 5) { |http| http.request(Net::HTTP::Get.new(uri)) }
      raise Unavailable unless response.is_a?(Net::HTTPSuccess)
      value = JSON.parse(response.body)
      raise Unavailable unless value.is_a?(Hash) && !value.key?('error')
      value
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Unavailable
    end

    def exchange(code)
      token = graph('oauth/access_token', client_id: ENV.fetch('META_OAUTH_APP_ID'), client_secret: ENV.fetch('META_APP_SECRET'), redirect_uri: callback_url, code: code).fetch('access_token')
      raise Unavailable unless token.is_a?(String) && token.length.between?(1, 8192)
      profile = graph('me', access_token: token, fields: 'id,name,email')
      permissions = graph('me/permissions', access_token: token, limit: 100).fetch('data')
      raise Unavailable unless profile['id'].to_s.match?(/\A\d+\z/) && permissions.is_a?(Array) && permissions.all? { |row| row.is_a?(Hash) && row['permission'].is_a?(String) }
      granted = permissions.select { |row| row['status'] == 'granted' }.map { |row| row.fetch('permission') }
      raise Unavailable unless (SCOPES - ['email'] - granted).empty?
      { 'access_token' => token, 'facebook_user_id' => profile['id'], 'name' => profile['name'], 'email' => profile['email'],
        'app_id' => ENV.fetch('META_OAUTH_APP_ID'), 'granted_permissions' => granted }
    rescue KeyError, TypeError
      raise Unavailable
    end
  end
end
