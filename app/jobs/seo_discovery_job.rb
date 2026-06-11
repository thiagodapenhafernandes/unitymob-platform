class SeoDiscoveryJob < ApplicationJob
  queue_as :default

  def perform(generate_ai: true)
    return unless Seo::DiscoveryService.enabled?

    Seo::DiscoveryService.new(generate_ai: generate_ai).call
  end
end
