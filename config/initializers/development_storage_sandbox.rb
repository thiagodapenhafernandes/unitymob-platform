# Development uploads must not reuse services restored from a production database.
if Rails.env.development?
  ActiveSupport.on_load(:active_storage_blob) do
    before_validation(on: :create) { self.service_name = "development_sandbox" }
  end
end

Rails.application.config.after_initialize do
  Storage::ActiveStorageRegistry.register_if_available! if Rails.env.development?
end
