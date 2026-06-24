Rails.application.config.to_prepare do
  Storage::ActiveStorageRegistry.register_if_available!
end
