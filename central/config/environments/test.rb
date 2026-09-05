Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.action_mailer.delivery_method = :test
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = false
  config.active_job.queue_adapter = :test
  config.active_storage.service = :test
  config.secret_key_base = "test-central-" * 12
  config.active_record.encryption.primary_key = "test-primary-" * 4
  config.active_record.encryption.deterministic_key = "test-deterministic-" * 4
  config.active_record.encryption.key_derivation_salt = "test-salt-" * 4
end
