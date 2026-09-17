class Admin::MarketingAlertsController < Admin::BaseController
  requires_permission :manage, :marketing

  def index
    insights = Seo::MarketingInsights.new(tenant: current_tenant)
    @alerts = insights.alerts
    @strategic_pages = insights.strategic_pages
  end
end
