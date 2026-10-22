require 'openssl'

module Webhooks
  module GatewaySignature
    module_function

    def valid?(body:, signature:)
      secret = ENV['WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET'].to_s
      return false if secret.empty?

      digest = signature.to_s.delete_prefix('sha256=')
      return false unless digest.match?(/\A[0-9a-f]{64}\z/)

      ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest('SHA256', secret, body), digest)
    end
  end
end
