module AccessControl
  module Settings
    ENFORCE_BROKER_IP_KEY = "access_control_enforce_broker_ip_allowlist".freeze
    ENFORCE_BROKER_DEVICE_KEY = "access_control_enforce_broker_trusted_devices".freeze

    module_function

    # Toggles por CONTA (colunas do tenant). Sem tenant no contexto ou
    # pré-migration, cai no Setting global antigo (comportamento preservado).
    def broker_ip_allowlist_enabled?(tenant: Current.tenant)
      if tenant && Tenant.column_names.include?("enforce_broker_ip_allowlist")
        return tenant.enforce_broker_ip_allowlist?
      end

      Setting.get(ENFORCE_BROKER_IP_KEY, "false").to_s == "true"
    end

    def broker_trusted_devices_enabled?(tenant: Current.tenant)
      if tenant && Tenant.column_names.include?("enforce_broker_trusted_devices")
        return tenant.enforce_broker_trusted_devices?
      end

      Setting.get(ENFORCE_BROKER_DEVICE_KEY, "false").to_s == "true"
    end
  end
end
