class Admin::MarketingCampaignsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_campaign, only: [:edit, :update, :destroy]

  def index
    @status = params[:status].to_s
    @campaigns = current_tenant.marketing_campaigns.includes(:seo_setting, :admin_user).recent
    @campaigns = @campaigns.where(status: @status) if @status.present?
    @campaigns = @campaigns.paginate(page: params[:page], per_page: 20)
  end

  def new
    @campaign = current_tenant.marketing_campaigns.new(
      seo_setting_id: params[:seo_setting_id],
      channel: params[:channel].presence || "organic",
      status: "idea",
      priority: 2
    )
    seed_from_seo_setting
  end

  def create
    @campaign = current_tenant.marketing_campaigns.new(campaign_params)
    @campaign.admin_user = current_admin_user

    if @campaign.save
      redirect_to admin_marketing_campaigns_path, notice: "Campanha criada com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @campaign.update(campaign_params)
      redirect_to admin_marketing_campaigns_path, notice: "Campanha atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @campaign.destroy
    redirect_to admin_marketing_campaigns_path, notice: "Campanha removida."
  end

  private

  def set_campaign
    @campaign = current_tenant.marketing_campaigns.find(params[:id])
  end

  def seed_from_seo_setting
    return unless @campaign.seo_setting

    @campaign.name ||= @campaign.seo_setting.display_name
    @campaign.target_url ||= @campaign.seo_setting.sanitized_canonical_path
    @campaign.objective ||= "Gerar tráfego qualificado e leads para esta página."
  end

  def campaign_params
    params.require(:marketing_campaign).permit(
      :seo_setting_id,
      :name,
      :channel,
      :status,
      :target_url,
      :objective,
      :budget,
      :utm_source,
      :utm_medium,
      :utm_campaign,
      :utm_term,
      :utm_content,
      :starts_on,
      :ends_on,
      :priority,
      :notes
    )
  end
end
