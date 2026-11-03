require 'net/http'
require 'uri'

module Gateway
  class ImovelwebClient
    class Error < StandardError; end
    class Unauthorized < Error; end

    def initialize(environment:)
      raise Error, 'Invalid environment' unless %w[sandbox production].include?(environment)
      @prefix = "IMOVELWEB_#{environment.upcase}"
      @base = ENV.fetch("#{@prefix}_API_URL").delete_suffix('/')
      uri = URI(@base)
      unless uri.scheme == 'https' && uri.host&.end_with?('.open.navent.com') && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.in?(['', '/'])
        raise Error, 'Use the official HTTPS API origin supplied by support'
      end
    end

    def associate_listing(client_code:, reference:, external_id:)
      request(:put, "/v1/inmobiliarias/#{segment(client_code)}/avisos/#{segment(reference)}/asociar/#{segment(external_id)}")
    end

    def configure_callbacks(url:, token:)
      uri = URI(url)
      raise Error, 'HTTPS callback and dedicated token required' unless uri.scheme == 'https' && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && token.to_s.length >= 32
      request(:put, '/v1/configuracion/callbacks', { url: url, authorizationHeaderKey: 'Authorization',
        authorizationHeaderValue: "Bearer #{token}", lenguajeCallbackBody: 'EN' })
      %w[CONTACTO CONTACTO_MENSAJE].each { |event| request(:put, "/v1/configuracion/callbacks/#{event}") }
    end

    def callbacks
      # Do not print this response: the provider returns the callback credential.
      request(:get, '/v1/configuracion/callbacks')
    end

    private

    def segment(value)
      URI.encode_www_form_component(value.to_s).gsub('+', '%20')
    end

    def access_token
      return @token if @token && @expires_at > Time.now + 30
      query = URI.encode_www_form(grant_type: 'client_credentials', client_id: ENV.fetch("#{@prefix}_CLIENT_ID"), client_secret: ENV.fetch("#{@prefix}_CLIENT_SECRET"))
      data = perform(:post, "/v1/application/login?#{query}")
      raise Error, 'Invalid token response' unless data.is_a?(Hash) && data['access_token'].is_a?(String) && data['access_token'].present? && data['expires_in'].to_i > 30
      @token = data.fetch('access_token')
      @expires_at = Time.now + data.fetch('expires_in').to_i
      @token
    end

    def request(method, path, body = nil)
      token = access_token
      begin
        perform(method, path, body, token: token)
      rescue Unauthorized
        @token = nil
        perform(method, path, body, token: access_token)
      end
    end

    def perform(method, path, body = nil, token: nil)
      uri = URI("#{@base}#{path}")
      req = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method).new(uri)
      req['Authorization'] = "Bearer #{token}" if token
      req['User-Agent'] = 'Unitymob/1.0 (contato@unitymob.com.br)'
      if body
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
      raise Unauthorized, "Imovelweb authentication failed" if response.code.to_i == 401
      raise Error, "Imovelweb HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body.to_s.empty? ? nil : JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error, 'Invalid Imovelweb response'
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError
      raise Error, 'Imovelweb communication failed'
    end
  end
end
