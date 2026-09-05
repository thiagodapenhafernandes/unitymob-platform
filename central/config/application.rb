require_relative "boot"
require "rails/all"
Bundler.require(*Rails.groups)
require_relative "../../support/engine"
module UnitymobCentral
  class Application < Rails::Application
    config.load_defaults 7.1
    config.action_mailer.logger = nil
    config.assets.paths << root.join("../app/assets/stylesheets")
    config.assets.paths << root.join("../app/assets/fonts")
    config.assets.paths << root.join("../app/assets/images")
    config.assets.precompile += %w[admin/theme_tokens.css admin/components.css turbo.js central_presence.js central_notifications.js]
    config.x.support_central = true
    config.time_zone = "Brasilia"
    config.i18n.default_locale = :'pt-BR'
    config.active_storage.draw_routes = false
    config.active_job.queue_adapter = :solid_queue
    config.active_record.encryption.primary_key = ENV["AR_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]
    config.filter_parameters += [:password, :password_confirmation, :code, :secret, :token, :otp_secret, :data, :body, :intake]
    config.middleware.use Rack::Attack
    config.session_store :cookie_store, key: "_unitymob_central", secure: Rails.env.production?, httponly: true, expire_after: 8.hours
  end
end
