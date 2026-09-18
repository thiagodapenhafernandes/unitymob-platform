require 'openssl'
require 'securerandom'
require 'uri'
require 'net/http'
require 'json'

module Gateway
  module AdminAuth
    module_function

    ITERATIONS = 210_000
    SESSION_TTL = 12 * 60 * 60
    CHALLENGE_TTL = 600

    def admin_email
      ENV.fetch('GATEWAY_ADMIN_EMAIL', 'contato@unitymob.com.br').strip.downcase
    end

    # Used offline (rake task) to produce the value stored in GATEWAY_ADMIN_PASSWORD_DIGEST.
    def hash_password(password)
      salt = SecureRandom.random_bytes(16)
      digest = OpenSSL::KDF.pbkdf2_hmac(password.to_s, salt: salt, iterations: ITERATIONS, length: 32, hash: 'sha256')
      "#{ITERATIONS}:#{salt.unpack1('H*')}:#{digest.unpack1('H*')}"
    end

    def valid_password?(password, stored)
      iterations, salt_hex, digest_hex = stored.to_s.split(':', 3)
      return false unless iterations && salt_hex && digest_hex
      computed = OpenSSL::KDF.pbkdf2_hmac(password.to_s, salt: [salt_hex].pack('H*'), iterations: iterations.to_i, length: 32, hash: 'sha256')
      Rack::Utils.secure_compare(computed.unpack1('H*'), digest_hex)
    rescue ArgumentError
      false
    end

    def digest(value)
      secret = ENV.fetch('GATEWAY_ADMIN_SECRET')
      raise ArgumentError, 'GATEWAY_ADMIN_SECRET must be at least 32 chars' if secret.length < 32
      OpenSSL::HMAC.hexdigest('SHA256', secret, value)
    end

    # Returns the opaque challenge token to keep in the browser session.
    def start_challenge
      token = SecureRandom.urlsafe_base64(32)
      code = format('%06d', SecureRandom.random_number(1_000_000))
      AdminLoginChallenge.create!(
        token_digest: digest(token),
        code_digest: digest("#{token}:#{code}"),
        expires_at: Time.now.utc + CHALLENGE_TTL
      )
      send_code(code)
      token
    end

    def verify_challenge(token, code)
      return false if token.to_s.empty?
      row = AdminLoginChallenge.find_by(token_digest: digest(token))
      return false unless row
      ok = false
      row.with_lock do
        next if row.consumed_at || row.expires_at <= Time.now.utc || row.attempts >= 5
        row.update!(attempts: row.attempts + 1)
        next unless Rack::Utils.secure_compare(row.code_digest, digest("#{token}:#{code}"))
        row.update!(consumed_at: Time.now.utc)
        ok = true
      end
      ok
    end

    # Local copy of DiscoveryLimit.allow?'s bucket logic, keyed with our own
    # secret so this doesn't depend on DISCOVERY_SECRET being configured.
    def rate_limited?(key, limit: 10, period: 600)
      bucket = Time.now.utc.to_i / period
      digest_key = digest("rate:#{key}:#{bucket}")
      record = DiscoveryLimit.create_or_find_by!(key: digest_key) { |row| row.expires_at = Time.at((bucket + 1) * period).utc }
      allowed = true
      record.with_lock do
        if record.hits >= limit
          allowed = false
        else
          record.update!(hits: record.hits + 1)
        end
      end
      !allowed
    end

    def send_code(code)
      key = ENV.fetch('RESEND_API_KEY')
      raise KeyError, 'Missing Resend configuration' if key.strip.empty?
      from = ENV['GATEWAY_ADMIN_MAIL_FROM'].presence || ENV.fetch('DISCOVERY_MAIL_FROM')
      uri = URI('https://api.resend.com/emails')
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{key}"
      request['Content-Type'] = 'application/json'
      request.body = {
        from: "Unitymob Gateway <#{from}>", to: [admin_email], subject: 'Código de acesso ao painel do Gateway',
        text: "Seu código de acesso: #{code}\nVálido por 10 minutos.\nSe você não tentou entrar no painel do gateway, ignore esta mensagem."
      }.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5, write_timeout: 5) do |http|
        http.request(request)
      end
      raise IOError, "Email delivery failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    end
  end
end
