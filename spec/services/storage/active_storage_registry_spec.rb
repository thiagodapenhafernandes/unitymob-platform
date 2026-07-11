require "rails_helper"

RSpec.describe Storage::ActiveStorageRegistry do
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
