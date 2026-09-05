require "net/http"
require "openssl"

class Support::Transport
  class DeliveryError < StandardError
    attr_reader :status
    def initialize(message, status: nil)
      @status = status
      super(message)
    end
  end

  def self.signature(secret, timestamp, body)
    OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
  end

  def self.post(account, path, payload)
    raise DeliveryError, "Endpoint inválido" unless Support::Account.valid_endpoint?(account.endpoint)
    uri = URI.join(account.endpoint, path)
    body = JSON.generate(payload)
    timestamp = Time.current.to_i.to_s
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Support-Account"] = account.uid
    request["X-Support-Timestamp"] = timestamp
    request["X-Support-Signature"] = signature(account.secret, timestamp, body)
    request.body = body
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 30, write_timeout: 30) { |http| http.request(request) }
    raise DeliveryError.new("Destino respondeu HTTP #{response.code}", status: response.code.to_i) unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body.presence || "{}")
  end
end
