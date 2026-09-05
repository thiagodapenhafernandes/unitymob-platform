module SupportDesk
  class Engine < Rails::Engine
    config.root = File.expand_path(__dir__)
    initializer "support_desk.paths" do |app|
      app.config.paths["db/migrate"] << root.join("db/migrate").to_s
      app.config.assets.precompile += %w[support_desk.css support_desk.js] if app.config.respond_to?(:assets)
    end
  end

  def self.central?
    Rails.application.config.x.support_central == true
  end
end
