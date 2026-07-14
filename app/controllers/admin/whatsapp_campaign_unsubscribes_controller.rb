class Admin::WhatsappCampaignUnsubscribesController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_campaigns) }, only: [:index]
  before_action -> { check_permission!(:manage, :whatsapp_campaigns) }, only: [:reenable]
  before_action :set_unsubscribe, only: [:reenable]

  def index
    @sender_numbers = current_tenant.whatsapp_sender_numbers.ordered
    @selected_sender_number = @sender_numbers.find_by(id: params[:whatsapp_sender_number_id])
    @status = params[:status].presence || "active"
    @query = params[:query].to_s.strip
    @unsubscribes = filtered_unsubscribes.paginate(page: params[:page], per_page: 30)
    @unsubscribe_metrics = unsubscribe_metrics
    @page_title = "Descadastros WhatsApp"
  end

  def reenable
    @unsubscribe.reenable!(
      admin_user: current_admin_user,
      reason: params[:reenable_reason]
    )
    redirect_back fallback_location: admin_whatsapp_campaign_unsubscribes_path,
                  notice: "Contato reabilitado para campanhas deste número."
  end

  private

  def set_unsubscribe
    @unsubscribe = filtered_unsubscribes.active.find(params[:id])
  end

  def filtered_unsubscribes
    scope = visible_unsubscribes_scope
    scope = scope.where(whatsapp_sender_number: @selected_sender_number) if @selected_sender_number
    scope = @status == "all" ? scope : scope.active
    if @query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      scope = scope.where("phone_number ILIKE :query OR contact_name ILIKE :query", query: like)
    end
    scope
  end

  def visible_unsubscribes_scope
    scoped_campaigns = current_tenant.whatsapp_campaigns

    owner_ids = visible_owner_ids(:whatsapp_campaigns)
    scoped_campaigns = scoped_campaigns.where(created_by_id: owner_ids) if owner_ids.present?

    current_tenant.whatsapp_campaign_unsubscribes.includes(
      :whatsapp_sender_number,
      :whatsapp_campaign,
      :whatsapp_campaign_recipient,
      :reenabled_by
    ).where(whatsapp_campaign_id: scoped_campaigns.select(:id)).or(
      current_tenant.whatsapp_campaign_unsubscribes.where(whatsapp_campaign_id: nil)
    ).recent
  end

  def unsubscribe_metrics
    base_scope = visible_unsubscribes_scope
    selected_scope = @selected_sender_number ? base_scope.where(whatsapp_sender_number: @selected_sender_number) : base_scope

    {
      active: base_scope.active.count,
      selected_active: selected_scope.active.count,
      reenabled: base_scope.reenabled.count
    }
  end
end
