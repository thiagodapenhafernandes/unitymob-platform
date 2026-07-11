module Storage
  module ActiveStorageRegistry
    module_function

    def register!(setting = StorageIntegrationSetting.current)
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

      register!
    rescue ActiveRecord::NoDatabaseError,
           ActiveRecord::StatementInvalid,
           ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError
      false
    end

    def fetch!(service_name)
      register!
      ActiveStorage::Blob.services.fetch(service_name.to_sym)
    end
  end
end
