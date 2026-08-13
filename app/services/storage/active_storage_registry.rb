module Storage
  module ActiveStorageRegistry
    module_function

    def register!(setting = StorageIntegrationSetting.current(tenant: Current.tenant))
      registry = ActiveStorage::Blob.services
      configurations = registry.instance_variable_get(:@configurations)
      services = registry.instance_variable_get(:@services)

      configurations = configurations.deep_dup
      add_static_compatibility_aliases!(configurations, setting)

      setting.active_storage_configurations.each do |name, config|
        key = name.to_sym
        configurations[key] = config.deep_symbolize_keys
        services.delete(key)
      end

      registry.instance_variable_set(:@configurations, configurations)
      registry.instance_variable_set(:@configurator, ActiveStorage::Service::Configurator.new(configurations))
      true
    end

    def add_static_compatibility_aliases!(configurations, setting)
      aliases = {
        StorageIntegrationSetting::DO_SERVICE_NAME => StorageIntegrationSetting::LEGACY_DO_SERVICE_NAMES,
        StorageIntegrationSetting::S3_SERVICE_NAME => StorageIntegrationSetting::LEGACY_S3_SERVICE_NAMES
      }

      aliases.each do |target, legacy_names|
        next if setting.active_storage_configurations.key?(target)

        source = legacy_names.find { |name| configurations.key?(name) }
        configurations[target] = configurations.fetch(source).deep_dup if source
      end
    end

    def register_if_available!
      return false unless ActiveRecord::Base.connection.data_source_exists?("storage_integration_settings")
      return false unless StorageIntegrationSetting.column_names.include?("tenant_id")

      StorageIntegrationSetting.find_each { |setting| register!(setting) }
      true
    rescue ActiveRecord::NoDatabaseError,
           ActiveRecord::StatementInvalid,
           ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError
      false
    end

    def fetch!(service_name)
      key = service_name.to_sym
      register_for_service_name!(key)
      add_dynamic_compatibility_alias!(key)
      ActiveStorage::Blob.services.fetch(key)
    end

    def register_for_service_name!(service_name)
      tenant_id = tenant_id_from_service_name(service_name)
      setting = StorageIntegrationSetting.find_by(tenant_id: tenant_id) if tenant_id
      register!(setting || StorageIntegrationSetting.current(tenant: Current.tenant))
    end

    def add_dynamic_compatibility_alias!(service_name)
      base_name = base_service_name_from_dynamic(service_name)
      return unless base_name

      registry = ActiveStorage::Blob.services
      configurations = registry.instance_variable_get(:@configurations)
      return if configurations.key?(service_name) || !configurations.key?(base_name)

      services = registry.instance_variable_get(:@services)
      configurations = configurations.deep_dup
      configurations[service_name] = configurations.fetch(base_name).deep_dup
      services.delete(service_name)
      registry.instance_variable_set(:@configurations, configurations)
      registry.instance_variable_set(:@configurator, ActiveStorage::Service::Configurator.new(configurations))
    end

    def tenant_id_from_service_name(service_name)
      service_name.to_s[/\A(?:do_spaces_db|amazon_s3_db)_tenant_(\d+)\z/, 1]&.to_i
    end

    def base_service_name_from_dynamic(service_name)
      case service_name.to_s
      when /\Ado_spaces_db_tenant_\d+\z/ then StorageIntegrationSetting::DO_SERVICE_NAME
      when /\Aamazon_s3_db_tenant_\d+\z/ then StorageIntegrationSetting::S3_SERVICE_NAME
      end
    end
  end
end
