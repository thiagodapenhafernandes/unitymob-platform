class Admin::MetaCampaignsController < Admin::BaseController
  requires_permission :manage, :marketing

  TABS = %w[funnel spend].freeze
  PERIODS = { "7" => 7, "30" => 30 }.freeze

  def index
    @tab = params[:tab].presence_in(TABS) || "funnel"
    @period_days = PERIODS[params[:period].to_s] || 30
    @ends_at = Time.current
    @starts_at = @period_days.days.ago.beginning_of_day
    @last_sync_at = MetaCampaignInsight.for_tenant(current_tenant).maximum(:updated_at)

    spend_by_campaign = spend_totals.index_by { |row| row.campaign_id.to_s }
    @spend_rows = spend_totals.sort_by { |row| -row.spend.to_f }
    @funnel_rows = Meta::CampaignFunnelQuery.new(tenant: current_tenant, starts_at: @starts_at, ends_at: @ends_at).call.rows
    @funnel_rows.each { |row| row[:spend] = spend_by_campaign[row[:campaign_id].to_s]&.spend.to_f }
    @funnel_rows.sort_by! { |row| [-row[:sales], -row[:visits], -row[:leads]] }
    @totals = build_totals(spend_by_campaign)
    @page_title = "Meta Ads"
  end

  def sync_now
    MetaInsightsSyncJob.perform_later(current_tenant.id)
    redirect_to admin_meta_campaigns_path(tab: params[:tab], period: params[:period]),
                notice: "Sincronização com a Meta iniciada. Os números atualizam em instantes."
  end

  private

  def spend_totals
    MetaCampaignInsight.for_tenant(current_tenant)
                       .where(date: @starts_at.to_date..@ends_at.to_date)
                       .group(:campaign_id)
                       .select(
                         "campaign_id, MAX(campaign_name) AS campaign_name, " \
                         "SUM(spend) AS spend, SUM(impressions) AS impressions, " \
                         "SUM(clicks) AS clicks, SUM(leads) AS leads"
                       )
  end

  def build_totals(spend_by_campaign)
    spend = spend_by_campaign.values.sum { |row| row.spend.to_f }
    meta_leads = spend_by_campaign.values.sum { |row| row.leads.to_i }
    crm_leads = @funnel_rows.sum { |row| row[:leads] }
    qualified = @funnel_rows.sum { |row| row[:qualified] }
    visits = @funnel_rows.sum { |row| row[:visits] }
    sales = @funnel_rows.sum { |row| row[:sales] }
    {
      spend: spend, meta_leads: meta_leads, crm_leads: crm_leads,
      qualified: qualified, visits: visits, sales: sales,
      cpl: meta_leads.positive? ? spend / meta_leads : nil,
      cost_per_sale: sales.positive? ? spend / sales : nil
    }
  end
end
