Rails.application.config.after_initialize do
  next unless defined?(Storage::ActiveStorageRegistry)

  job_classes = []
  job_classes << ActiveStorage::AnalyzeJob if defined?(ActiveStorage::AnalyzeJob)
  job_classes << ActiveStorage::PurgeJob if defined?(ActiveStorage::PurgeJob)
  job_classes << ActiveStorage::TransformJob if defined?(ActiveStorage::TransformJob)

  job_classes.each do |job_class|
    job_class.before_perform do
      Storage::ActiveStorageRegistry.register_if_available!
    end
  end
end

module ActiveStorageDynamicServices
  module ControllerHook
    extend ActiveSupport::Concern

    included do
      prepend_before_action :register_dynamic_active_storage_services
    end

    private

    def register_dynamic_active_storage_services
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)
    end
  end
end

Rails.application.config.to_prepare do
  %w[
    ActiveStorage::Blobs::RedirectController
    ActiveStorage::Blobs::ProxyController
    ActiveStorage::Representations::RedirectController
    ActiveStorage::Representations::ProxyController
  ].filter_map(&:safe_constantize).each do |controller|
    next if controller < ActiveStorageDynamicServices::ControllerHook

    controller.include(ActiveStorageDynamicServices::ControllerHook)
  end
end
