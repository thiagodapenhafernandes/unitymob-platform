class Admin::MarketingPropertiesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }

  def index
    @property_insights = Seo::MarketingInsights.new(tenant: current_tenant).property_insights(limit: 40)
  end
end
