module Storage
  class ConnectionTester
    Result = Struct.new(:ok?, :message, keyword_init: true)

    def initialize(setting:, provider:)
      @setting = setting
      @provider = provider.to_s
    end

    def call
      return test_local if provider == "local"
      return missing_configuration unless setting.test_ready_for?(provider)

      service_name = setting.service_name_for_provider(provider)
      service = Storage::ActiveStorageRegistry.fetch!(service_name)
      key = ["diagnostics", "storage-test-#{SecureRandom.hex(8)}.txt"].join("/")
      io = StringIO.new("unitymob storage test #{Time.current.to_i}")
      service.upload(key, io)
      service.delete(key)
      Result.new(ok?: true, message: "Conexão validada com upload e remoção de teste.")
    rescue StandardError => e
      Result.new(ok?: false, message: "#{e.class}: #{e.message}")
    end

    private

    attr_reader :setting, :provider

    def test_local
      root = Rails.root.join("storage")
      FileUtils.mkdir_p(root)
      path = root.join("storage-test-#{SecureRandom.hex(8)}.txt")
      File.write(path, "unitymob local storage test")
      File.delete(path) if File.exist?(path)
      Result.new(ok?: true, message: "Storage local gravou e removeu arquivo de teste.")
    rescue StandardError => e
      Result.new(ok?: false, message: "#{e.class}: #{e.message}")
    end

    def missing_configuration
      Result.new(ok?: false, message: "Configuração incompleta para #{StorageIntegrationSetting::PROVIDER_LABELS.fetch(provider, provider)}.")
    end
  end
end
