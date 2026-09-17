class Admin::SeoDashboardController < Admin::BaseController
  requires_permission :manage, :site_publico

  def index
    @period = params[:period].presence_in(%w[7 30 90 all]) || "30"
    @dashboard = Seo::DashboardMetrics.new(period: @period, tenant: current_tenant).call
  end
end
