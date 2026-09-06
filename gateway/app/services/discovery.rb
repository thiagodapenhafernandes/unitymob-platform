require 'openssl'
require 'securerandom'
require 'uri'
require 'net/http'
require 'json'

module Gateway
  module Discovery
    module_function

    def instance(id)
      JSON.parse(ENV.fetch('DISCOVERY_INSTANCES', '{}'))[id]
    end

    def origin(value)
      uri = URI.parse(value.to_s)
      raise ArgumentError unless uri.is_a?(URI::HTTPS) && uri.host && uri.port == 443 &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && ['', '/'].include?(uri.path)
      raise ArgumentError if %w[localhost 127.0.0.1 ::1].include?(uri.host)
      "https://#{uri.host}"
    end

    def digest(value)
      secret = ENV.fetch('DISCOVERY_SECRET')
      raise ArgumentError if secret.length < 32
      OpenSSL::HMAC.hexdigest('SHA256', secret, value)
    end

    def email(value)
      normalized = value.to_s.strip.downcase
      raise ArgumentError unless normalized.length <= 254 && normalized.match?(URI::MailTo::EMAIL_REGEXP) && !normalized.match?(/[\r\n]/)
      normalized
    end

    def send_code(address, code)
      from = email(ENV.fetch('DISCOVERY_MAIL_FROM'))
      key = ENV.fetch('RESEND_API_KEY')
      raise KeyError, 'Missing Resend configuration' if key.strip.empty?
      uri = URI('https://api.resend.com/emails')
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{key}"
      request['Content-Type'] = 'application/json'
      request.body = {
        from: "Unitymob <#{from}>", to: [email(address)], subject: 'Código de conexão Unitymob',
        text: "Seu código: #{code}\nVálido por 10 minutos para localizar suas contas. Este código não substitui o login no CRM.\nSe não solicitou, ignore esta mensagem."
      }.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5, write_timeout: 5) do |http|
        http.request(request)
      end
      raise IOError, "Email delivery failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      raise IOError, 'Invalid email delivery response' unless result.is_a?(Hash) && result['id'].is_a?(String) && !result['id'].empty?
      result['id']
    end
  end
end
