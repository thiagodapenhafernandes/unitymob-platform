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
      unless uri.scheme == 'https' && (uri.host == 'api-br-open.navent.com' || uri.host&.end_with?('.open.navent.com')) && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.in?(['', '/'])
        raise Error, 'Use the official HTTPS API origin supplied by support'
      end
    end

    def authorization_script(client_code:)
      integrator = ENV["#{@prefix}_INTEGRATOR_ID"].to_s
      raise Error, 'Integrator login is not configured' unless integrator.match?(/\A[A-Za-z0-9_-]+\z/)
      "https://loginbr-open.navent.com/#{segment(integrator)}/#{segment(client_code)}.js"
    end

    def authorized_advertiser(client_code:)
      # Only an exact server-generated code proves which customer completed Login.
      seen = 0
      100.times do |page|
        data = request(:get, "/v1/imobiliarias?pageable.page=#{page}&pageable.size=100")
        return nil if data.nil?
        raise Error, 'Invalid advertiser response' unless data.is_a?(Hash) && data['content'].is_a?(Array)
        matches = data['content'].select { |item| item.is_a?(Hash) && item['codigoInmobiliaria'] == client_code }
        raise Error, 'Ambiguous advertiser response' if matches.size > 1
        if (advertiser = matches.first)
          raise Error, 'Advertiser is blocked' if advertiser['bloqueada'] == true
          id = advertiser['idNavplat'].to_s
          raise Error, 'Invalid advertiser identity' unless id.match?(/\A[0-9]+\z/)
          return { client_code: client_code, advertiser_code: id }
        end
        seen += data['content'].size
        return nil if data['content'].empty? || (data['total'].is_a?(Numeric) && seen >= data['total'])
      end
      raise Error, 'Advertiser pagination limit reached'
    end

    def associate_online_listings(client_code:, page:)
      data = request(:get, "/v1/imobiliarias/#{segment(client_code)}/anuncios/online/resumo?pageable.page=#{page}&pageable.size=5")
      return { associated: 0, next_page: nil } if data.nil?
      raise Error, 'Invalid listing response' unless data.is_a?(Hash) && data['content'].is_a?(Array) && data['number'] == page && data['total'].is_a?(Numeric)
      raise Error, 'Invalid listing page size' if data['content'].size > 5
      associated = 0
      data['content'].each do |listing|
        raise Error, 'Invalid listing identity' unless listing.is_a?(Hash) && listing['idAvisoNavplat'].to_s.match?(/\A[0-9]+\z/)
        next if listing['codigoAviso'].present?
        id = listing['idAvisoNavplat'].to_s
        associate_listing(client_code: client_code, reference: "iw-#{id}", external_id: id)
        associated += 1
      end
      next_page = page + 1 if data['content'].any? && (page * 5 + data['content'].size) < data['total']
      { associated: associated, next_page: next_page }
    end

    def associate_listing(client_code:, reference:, external_id:)
      request(:put, "/v1/imobiliarias/#{segment(client_code)}/anuncios/#{segment(reference)}/asociar/#{segment(external_id)}")
    end

    def configure_callbacks(url:, token:)
      uri = URI(url)
      raise Error, 'HTTPS callback and dedicated token required' unless uri.scheme == 'https' && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && token.to_s.length >= 32
      request(:put, '/v1/configuracao/callbacks', { url: url, authorizationHeaderKey: 'Authorization',
        authorizationHeaderValue: "Bearer #{token}", lenguajeCallbackBody: 'EN' })
      %w[CONTACTO CONTACTO_MENSAJE].each { |event| request(:put, "/v1/configuracao/callbacks/#{event}?evento=#{event}") }
    end

    def callbacks
      # Do not print this response: the provider returns the callback credential.
      request(:get, '/v1/configuracao/callbacks')
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
