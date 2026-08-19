# frozen_string_literal: true

require "openssl"

module Gateway
  module InternalSignature
    module_function

    def sign(raw_body, secret:)
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, raw_body.to_s)}"
    end
  end
end
