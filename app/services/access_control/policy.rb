module AccessControl
  class Policy
    Result = Struct.new(:allowed?, :reason, :device, keyword_init: true)

    def self.call(admin_user:, request:, controller: nil, trusted_device: nil)
      new(admin_user: admin_user, request: request, controller: controller, trusted_device: trusted_device).call
    end

    def initialize(admin_user:, request:, controller: nil, trusted_device: nil)
      @admin_user = admin_user
      @request = request
      @controller = controller
      @trusted_device = trusted_device
    end

    def call
      return denied("IP bloqueado para login administrativo") if blocked_ip?
      return denied("IP fora da lista permitida para este usuário") if ip_allowlist_required? && !allowed_ip?

      current_device = device
      if trusted_device_required?
        return denied("Dispositivo bloqueado", current_device) if current_device&.status == "blocked"
        return denied("Dispositivo aguardando aprovação", current_device) unless current_device&.status == "trusted"
      end

      Result.new(allowed?: true, reason: "Acesso permitido", device: current_device)
    end

    private

    attr_reader :admin_user, :request, :controller

    def denied(reason, current_device = device)
      Result.new(allowed?: false, reason: reason, device: current_device)
    end

    def ip
      request.remote_ip.to_s
    end

    def matching_rules(rule_type)
      AccessControlRule.matching_ip_for_tenant(ip, admin_user&.tenant).select do |rule|
        rule.rule_type == rule_type && rule.applies_to_user?(admin_user)
      end
    end

    def blocked_ip?
      matching_rules("block_ip").any?
    end

    def allowed_ip?
      matching_rules("allow_ip").any?
    end

    def ip_allowlist_required?
      admin_user.require_ip_allowlist? || broker_global_rule_enabled?
    end

    def trusted_device_required?
      admin_user.require_trusted_device? || AccessControl::Settings.broker_trusted_devices_enabled?(tenant: admin_user.tenant) && broker?
    end

    def broker_global_rule_enabled?
      AccessControl::Settings.broker_ip_allowlist_enabled?(tenant: admin_user.tenant) && broker?
    end

    def broker?
      admin_user.present? && !admin_user.system_admin? && !admin_user.admin?
    end

    def device
      return @device if defined?(@device)
      # Somente chamadas internas passam o dispositivo de uma concessão autenticada.
      if @trusted_device && @trusted_device.admin_user_id == admin_user.id && @trusted_device.tenant_id == admin_user.tenant_id
        return @device = @trusted_device
      end
      return @device = nil unless controller

      @device = AccessControl::DeviceRegistry.call(controller, admin_user)
    end
  end
end
