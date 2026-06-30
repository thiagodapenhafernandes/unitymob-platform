class Admin::WhatsappCampaignRecipientsController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_campaigns) }

  def index
    @sender_numbers = current_tenant.whatsapp_sender_numbers.ordered
    @selected_sender_number = @sender_numbers.find_by(id: params[:whatsapp_sender_number_id])
    @source = params[:source].presence || "spreadsheet"
    @conversion_status = params[:conversion_status].presence
    @query = params[:query].to_s.strip
    @recipients = filtered_recipients.paginate(page: params[:page], per_page: 40)
    @page_title = "Importados CSV"
  end

  private

  def filtered_recipients
    scope = current_tenant.whatsapp_campaign_recipients
      .includes(:whatsapp_campaign, :lead, :admin_user)
      .joins(:whatsapp_campaign)
      .order(created_at: :desc)

    owner_ids = visible_owner_ids(:whatsapp_campaigns)
    scope = scope.where(whatsapp_campaigns: { created_by_id: owner_ids }) if owner_ids.present?
    scope = scope.where(whatsapp_campaigns: { whatsapp_sender_number_id: @selected_sender_number.id }) if @selected_sender_number
    scope = scope.where(source: @source) if WhatsappCampaignRecipient::SOURCES.include?(@source)
    scope = scope.where(conversion_status: @conversion_status) if WhatsappCampaignRecipient::CONVERSION_STATUSES.include?(@conversion_status)

    if @query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      scope = scope.where(
        "whatsapp_campaign_recipients.name ILIKE :query OR whatsapp_campaign_recipients.phone_number ILIKE :query OR whatsapp_campaign_recipients.email ILIKE :query",
        query: like
      )
    end

    scope
  end
end
