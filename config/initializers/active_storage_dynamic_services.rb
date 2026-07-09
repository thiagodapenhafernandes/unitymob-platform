Rails.application.config.after_initialize do
  next unless defined?(Storage::ActiveStorageRegistry)

  job_classes = []
  job_classes << ActiveStorage::AnalyzeJob if defined?(ActiveStorage::AnalyzeJob)
  job_classes << ActiveStorage::TransformJob if defined?(ActiveStorage::TransformJob)

  job_classes.each do |job_class|
    job_class.before_perform do
      Storage::ActiveStorageRegistry.register_if_available!
    end
  end
end
