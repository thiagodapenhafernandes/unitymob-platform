class Admin::MarketingOpportunitiesController < Admin::BaseController
  requires_permission :manage, :marketing

  def index
    @insights = Seo::MarketingInsights.new(tenant: current_tenant).call
  end
end
