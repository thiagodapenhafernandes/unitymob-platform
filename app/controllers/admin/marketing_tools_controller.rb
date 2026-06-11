class Admin::MarketingToolsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }

  def index
    @campaign = MarketingCampaign.find_by(id: params[:campaign_id]) || MarketingCampaign.new(
      name: params[:name],
      target_url: params[:target_url].presence || "/imoveis",
      channel: params[:channel].presence || "organic",
      utm_source: params[:utm_source],
      utm_medium: params[:utm_medium],
      utm_campaign: params[:utm_campaign],
      utm_term: params[:utm_term],
      utm_content: params[:utm_content]
    )
  end
end
