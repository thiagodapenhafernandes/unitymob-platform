class Admin::MarketingAlertsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }

  def index
    @alerts = Seo::MarketingInsights.new.alerts
    @strategic_pages = Seo::MarketingInsights.new.strategic_pages
  end
end
