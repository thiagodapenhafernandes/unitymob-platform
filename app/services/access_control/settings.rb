module AccessControl
  module Settings
    ENFORCE_BROKER_IP_KEY = "access_control_enforce_broker_ip_allowlist".freeze
    ENFORCE_BROKER_DEVICE_KEY = "access_control_enforce_broker_trusted_devices".freeze

    module_function

    def broker_ip_allowlist_enabled?
      Setting.get(ENFORCE_BROKER_IP_KEY, "false").to_s == "true"
    end

    def broker_trusted_devices_enabled?
      Setting.get(ENFORCE_BROKER_DEVICE_KEY, "false").to_s == "true"
    end
  end
end
