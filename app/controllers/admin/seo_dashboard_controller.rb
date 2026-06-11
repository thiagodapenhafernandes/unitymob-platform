class Admin::SeoDashboardController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }

  def index
    @period = params[:period].presence_in(%w[7 30 90 all]) || "30"
    @dashboard = Seo::DashboardMetrics.new(period: @period).call
  end
end
