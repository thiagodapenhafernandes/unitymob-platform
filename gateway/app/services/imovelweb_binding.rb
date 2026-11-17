module Gateway
  class ImovelwebBinding
    class Error < StandardError; end

    def initialize(environment:, client_code:, client_key:)
      @environment, @code, @key = environment, client_code, client_key
    end

    def verification(proof: nil)
      advertiser = ImovelwebClient.new(environment: @environment).authorized_advertiser(client_code: @code, administrator: true)
      return { confirmed: false } unless advertiser
      others = WebhookRoute.where(provider: 'imovelweb', imovelweb_environment: @environment).where.not(client_key: @key)
      if others.where(imovelweb_client_code: @code).exists? || others.where(imovelweb_advertiser_code: advertiser[:advertiser_code]).exists?
        raise Error, 'advertiser_already_linked'
      end
      own = WebhookRoute.find_by(provider: 'imovelweb', client_key: @key, imovelweb_client_code: @code, imovelweb_environment: @environment)
      confirmed = (own.present? && (own.active? || own.imovelweb_advertiser_code == advertiser[:advertiser_code])) || valid_proof?(proof)
      { confirmed: confirmed, advertiser_code: advertiser[:advertiser_code], ownership_required: !confirmed,
        email_hint: email_hint(advertiser[:administrator_email]) }
    end

    def start
      data = verification
      raise Error, 'consent_pending' unless data[:ownership_required]
      raise Error, 'rate_limited' if AdminAuth.rate_limited?("imovelweb-binding:#{@environment}:#{@code}", limit: 3, period: 600)
      advertiser = ImovelwebClient.new(environment: @environment).authorized_advertiser(client_code: @code, administrator: true)
      address = advertiser&.fetch(:administrator_email)
      raise Error, 'administrator_email_unavailable' if address.blank?
      token = SecureRandom.urlsafe_base64(32)
      code = format('%06d', SecureRandom.random_number(1_000_000))
      row = ImovelwebBindingChallenge.create!(token_digest: AdminAuth.digest(token), code_digest: AdminAuth.digest("#{token}:#{code}"),
        client_key: @key, client_code: @code, environment: @environment, expires_at: 10.minutes.from_now)
      begin
        Discovery.send_code(address, code, purpose: :imovelweb_binding)
      rescue StandardError
        row.update!(consumed_at: Time.now.utc)
        raise Error, 'email_delivery_failed'
      end
      { challenge_token: token, email_hint: email_hint(address) }
    end

    def confirm(token:, code:)
      row = challenge(token)
      raise Error, 'invalid_code' unless row && code.to_s.match?(/\A[0-9]{6}\z/)
      verified = false
      row.with_lock do
        raise Error, 'invalid_code' if row.consumed_at || row.expires_at <= Time.now.utc || row.attempts >= 5
        row.update!(attempts: row.attempts + 1)
        # Commit the failed attempt before reporting it to the caller.
        verified = Rack::Utils.secure_compare(row.code_digest, AdminAuth.digest("#{token}:#{code}"))
        next unless verified
        row.update!(verified_at: Time.now.utc)
      end
      raise Error, 'invalid_code' unless verified
      { binding_proof: proof_for(token) }
    end

    def valid_proof?(proof)
      return false unless proof.to_s.match?(/\A[0-9a-f]{64}\z/)
      ImovelwebBindingChallenge.where(client_key: @key, client_code: @code, environment: @environment,
        consumed_at: nil).where.not(verified_at: nil).where('expires_at > ?', Time.now.utc).any? do |row|
        Rack::Utils.secure_compare(proof, AdminAuth.digest("imovelweb-proof:#{row.token_digest}"))
      end
    end

    def consume_proof!(proof)
      row = ImovelwebBindingChallenge.where(client_key: @key, client_code: @code, environment: @environment,
        consumed_at: nil).where.not(verified_at: nil).where('expires_at > ?', Time.now.utc).find do |item|
        Rack::Utils.secure_compare(proof.to_s, AdminAuth.digest("imovelweb-proof:#{item.token_digest}"))
      end
      row&.update!(consumed_at: Time.now.utc)
    end

    private

    def challenge(token)
      return if token.to_s.blank?
      ImovelwebBindingChallenge.find_by(token_digest: AdminAuth.digest(token), client_key: @key, client_code: @code, environment: @environment)
    end

    def proof_for(token)
      AdminAuth.digest("imovelweb-proof:#{AdminAuth.digest(token)}")
    end

    def email_hint(address)
      return if address.blank?
      local, domain = address.split('@', 2)
      "#{local[0]}***@#{domain}"
    end
  end
end
