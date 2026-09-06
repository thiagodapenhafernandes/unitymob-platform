module Mobile
  class AccountMembershipRegistrar
    def self.configured?
      ENV['DISCOVERY_INSTANCE_ID'].present? && ENV['DISCOVERY_INSTANCE_TOKEN'].to_s.length >= 32 && ENV['DISCOVERY_GATEWAY_URL'].present?
    end
    def self.sync!(user)
      return unless user.tenant_id
      identity = user.login_identity
      membership = AccountMembership.where(tenant_id: user.tenant_id, member_admin_user_id: user.id).order(updated_at: :desc).first if user.mirror?
      active = user.active? && identity.active? && !user.super_admin? && (!user.mirror? || membership&.active?)
      publish!(tenant_id: user.tenant_id.to_s, user_id: user.id.to_s, email: identity.email,
        tenant_name: user.tenant&.name, active: !!active, source_updated_at: [user.updated_at, identity.updated_at, membership&.updated_at].compact.max.utc.iso8601(6))
    end
    def self.publish!(payload)
      return unless configured?
      response = Faraday.new(url: ENV.fetch('DISCOVERY_GATEWAY_URL'), request: {open_timeout: 5, timeout: 10}).post('/internal/discovery/v2/memberships') do |request|
        request.headers['Authorization'] = "Bearer #{ENV.fetch('DISCOVERY_INSTANCE_TOKEN')}"
        request.headers['X-Unitymob-Instance'] = ENV.fetch('DISCOVERY_INSTANCE_ID')
        request.headers['Content-Type'] = 'application/json'
        request.body = payload.to_json
      end
      raise Faraday::Error, "Discovery synchronization failed (#{response.status})" unless response.success?
    end
  end
end
