# frozen_string_literal: true

require "openssl"
require "rack/utils"

module Gateway
  module MetaSignature
    module_function

    def valid?(raw_body, signature, app_secret:)
      return false if raw_body.to_s.empty? || signature.to_s.empty? || app_secret.to_s.empty?

      Rack::Utils.secure_compare(sign(raw_body, app_secret:), signature.to_s)
    rescue ArgumentError
      false
    end

    def sign(raw_body, app_secret:)
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", app_secret.to_s, raw_body.to_s)}"
    end
  end
end
