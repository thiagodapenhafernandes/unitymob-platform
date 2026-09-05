Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.force_ssl = true
  config.consider_all_requests_local = false
  config.active_storage.service = :private_spaces
  config.log_level = :info
  config.hosts = ["admin.unitymob.com.br"]
  config.public_file_server.enabled = true
  config.assets.compile = false
end
