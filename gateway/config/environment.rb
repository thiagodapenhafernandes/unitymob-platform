# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "active_record"
require "erb"
require "yaml"

module Gateway
  class << self
    def root
      @root ||= File.expand_path("..", __dir__)
    end

    def env
      ENV.fetch("RACK_ENV", ENV.fetch("APP_ENV", "development"))
    end
  end

  module Database
    module_function

    def configurations
      path = File.join(Gateway.root, "config/database.yml")
      raw_config = ERB.new(File.read(path)).result
      YAML.safe_load(raw_config, aliases: true)
    end

    def connect!
      ActiveRecord::Base.establish_connection(configurations.fetch(Gateway.env))
    end
  end
end

ActiveRecord::Base.configurations = Gateway::Database.configurations
Gateway::Database.connect!

require_relative "../app/models/application_record"
Dir[File.join(Gateway.root, "app/models/**/*.rb")].sort.each { |file| require file }
Dir[File.join(Gateway.root, "app/services/**/*.rb")].sort.each { |file| require file }
require_relative "../app/gateway_app"
