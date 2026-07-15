require "rails_helper"

RSpec.describe Storage::ActiveStorageRegistry do
  describe ".register!" do
    it "persiste o alias no registry usado pelo Active Storage" do
      registry = ActiveStorage::Blob.services
      original_configurations = registry.instance_variable_get(:@configurations)
      original_services = registry.instance_variable_get(:@services)
      registry.instance_variable_set(:@configurations, { do_spaces: { service: "Disk", root: Rails.root.join("tmp/storage") } })
      registry.instance_variable_set(:@services, {})
      setting = instance_double(StorageIntegrationSetting, active_storage_configurations: {})

      described_class.register!(setting)

      expect(registry.instance_variable_get(:@configurations)).to have_key(:do_spaces_db)
    ensure
      registry.instance_variable_set(:@configurations, original_configurations)
      registry.instance_variable_set(:@services, original_services)
      registry.instance_variable_set(:@configurator, ActiveStorage::Service::Configurator.new(original_configurations))
    end
  end

  describe "Active Storage job hooks" do
    it "registra serviços dinâmicos antes do purge job nativo" do
      blob = instance_double(ActiveStorage::Blob)

      allow(Storage::ActiveStorageRegistry).to receive(:register_if_available!)
      allow(blob).to receive(:purge)

      ActiveStorage::PurgeJob.perform_now(blob)

      expect(Storage::ActiveStorageRegistry).to have_received(:register_if_available!).ordered
      expect(blob).to have_received(:purge).ordered
    end
  end

  describe ".add_static_compatibility_aliases!" do
    it "expõe do_spaces_db usando a configuração estática legada" do
      legacy = { service: "S3", bucket: "legacy-bucket" }
      configurations = { do_spaces: legacy }
      setting = instance_double(StorageIntegrationSetting, active_storage_configurations: {})

      described_class.add_static_compatibility_aliases!(configurations, setting)

      expect(configurations[:do_spaces_db]).to eq(legacy)
      expect(configurations[:do_spaces_db]).not_to equal(legacy)
    end

    it "preserva a configuração dinâmica quando ela está disponível" do
      configurations = { do_spaces: { service: "S3", bucket: "legacy" } }
      setting = instance_double(
        StorageIntegrationSetting,
        active_storage_configurations: { do_spaces_db: { service: "S3", bucket: "dynamic" } }
      )

      described_class.add_static_compatibility_aliases!(configurations, setting)

      expect(configurations).not_to have_key(:do_spaces_db)
    end
  end
end
