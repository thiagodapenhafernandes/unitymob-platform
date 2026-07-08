require_relative "boot"
require "uri"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module UnitymobCrm
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    config.hosts << "dev.notificalead.com.br"
    config.hosts << "143.110.138.67"
    config.hosts << "unitymob.com.br"
    config.hosts << "www.unitymob.com.br"
    config.hosts << "localhost"
    config.hosts << "127.0.0.1"
    config.hosts << "dev.unitymob.com.br"

    app_host = ENV["APP_HOST"].to_s.strip
    if app_host.present?
      parsed_host = URI.parse(app_host).host if app_host.match?(%r{\Ahttps?://}i)
      config.hosts << (parsed_host.presence || app_host)
    end

    ENV.fetch("ADDITIONAL_ALLOWED_HOSTS", "").split(/[,\s]+/).each do |host|
      config.hosts << host.strip if host.strip.present?
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Brasilia"
    config.i18n.default_locale = :'pt-BR'

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Active Storage configuration
    config.active_storage.variant_processor = :mini_magick
    config.active_storage.content_types_allowed_inline << "image/svg+xml"
    config.active_storage.content_types_to_serve_as_binary.delete("image/svg+xml")

    # Usar structure.sql em vez de schema.rb: necessário para tipos PostGIS
    # (geography/geometry) que o schema dumper do Rails não entende
    # nativamente. structure.sql é gerado com pg_dump e preserva tudo.
    config.active_record.schema_format = :sql
  end
end
