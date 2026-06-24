module Storage
  module ActiveStorageRegistry
    module_function

    def register!(setting = StorageIntegrationSetting.current)
      registry = ActiveStorage::Blob.services
      configurations = registry.instance_variable_get(:@configurations)
      services = registry.instance_variable_get(:@services)

      setting.active_storage_configurations.each do |name, config|
        key = name.to_sym
        configurations[key] = config.deep_symbolize_keys
        services.delete(key)
      end

      registry.instance_variable_set(:@configurator, ActiveStorage::Service::Configurator.new(configurations))
      true
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
