require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # 404/422 são respostas esperadas para URLs antigas, bots e scanners. Evita
  # stack traces de RoutingError no Puma sem esconder exceções reais (5xx).
  config.action_dispatch.log_rescued_responses = false

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  # config.public_file_server.enabled = false

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on local disk or DigitalOcean Spaces.
  storage_service = if ENV["ACTIVE_STORAGE_SERVICE"].present?
    ENV["ACTIVE_STORAGE_SERVICE"]
  elsif ENV["VISTASOFT_SPACES_MIRROR_ENABLED"] == "true"
    "do_spaces"
  else
    "local"
  end
  config.active_storage.service = storage_service.to_sym

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # URLs generated outside a request (mailers/jobs) need an explicit host.
  public_app_url = URI.parse(ENV.fetch("APP_HOST", "https://saluteimoveis.com.br"))
  config.action_mailer.default_url_options = {
    host: public_app_url.host,
    protocol: public_app_url.scheme
  }

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Lograge: 1 linha JSON por request (método, path, status, duração, db/view).
  # request_id correlaciona com os demais logs; host identifica o tenant no
  # white-label sem custar query.
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_payload do |controller|
    {
      request_id: controller.request.request_id,
      host: controller.request.host
    }
  end

  # Cache em memória por processo. Solid Queue continua sendo a fila de jobs;
  # o cache aqui é apenas para leituras síncronas curtas do site público.
  config.cache_store = :memory_store, {
    size: ENV.fetch("RAILS_MEMORY_CACHE_SIZE_MB", 64).to_i.megabytes,
    expires_in: 1.day
  }

  # Use a real queuing backend for Active Job (and separate queues per environment).
  config.active_job.queue_adapter = :solid_queue
  # Analise de imagens pode abrir arquivos grandes. Mantem esse trabalho fora
  # das filas operacionais de check-in, notificacoes e e-mail.
  config.active_storage.queues.analysis = :media
  # config.active_job.queue_name_prefix = "unitymob_crm_production"

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
