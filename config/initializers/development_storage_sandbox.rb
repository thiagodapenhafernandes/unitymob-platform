# Development uploads must not reuse services restored from a production database.
# New blobs always go to local disk; blobs already on development_sandbox keep
# resolving through their stored service_name.
if Rails.env.development?
  ActiveSupport.on_load(:active_storage_blob) do
    before_validation(on: :create) { self.service_name = "local" }
  end
end

Rails.application.config.after_initialize do
  Storage::ActiveStorageRegistry.register_if_available! if Rails.env.development?
end
