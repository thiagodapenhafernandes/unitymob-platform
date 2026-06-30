module AccessControl
  class DeviceRegistry
    COOKIE_KEY = "salute_admin_device_id".freeze

    def self.call(controller, admin_user)
      new(controller, admin_user).call
    end

    def initialize(controller, admin_user)
      @controller = controller
      @admin_user = admin_user
    end

    def call
      fingerprint = device_fingerprint
      device = trusted_device_scope.find_or_initialize_by(admin_user: admin_user, fingerprint: fingerprint)
      device.assign_attributes(device_attributes)
      device.save!
      device
    rescue ActiveRecord::RecordNotUnique => error
      device = TrustedDevice.where(admin_user: admin_user, fingerprint: fingerprint).first
      raise error unless device

      device.tenant = admin_user.system_admin? ? nil : admin_user.tenant
      device.update!(device_attributes)
      device
    end

    private

    attr_reader :controller, :admin_user

    def trusted_device_scope
      return TrustedDevice.where(tenant_id: nil) if admin_user.system_admin?

      admin_user.tenant.trusted_devices
    end

    def device_fingerprint
      existing = cookie_jar.signed[COOKIE_KEY].presence
      return existing if existing

      SecureRandom.uuid.tap do |fingerprint|
        cookie_jar.signed.permanent[COOKIE_KEY] = {
          value: fingerprint,
          httponly: true,
          same_site: :lax
        }
      end
    end

    def device_attributes
      device = AccessAudit::DeviceParser.call(controller.request.user_agent.to_s)
      {
        name: default_name(device),
        device_type: device[:device_type],
        browser: device[:browser],
        platform: device[:platform],
        last_ip: controller.request.remote_ip,
        user_agent: controller.request.user_agent.to_s.first(255),
        last_seen_at: Time.current
      }.compact
    end

    def default_name(device)
      [device[:device_type], device[:browser], device[:platform]].compact_blank.join(" · ").presence
    end

    def cookie_jar
      controller.send(:cookies)
    end
  end
end
