class RefreshFeaturedPropertiesJob < ApplicationJob
  queue_as :default
  
  def perform
    Rails.logger.info "Refreshing featured properties materialized view"
    
    ActiveRecord::Base.connection.execute(
      "REFRESH MATERIALIZED VIEW CONCURRENTLY featured_properties_view"
    )
    
    Rails.logger.info "Featured properties view refreshed successfully"
  rescue StandardError => e
    Rails.logger.error "Failed to refresh featured properties view: #{e.message}"
    raise
  end
end
