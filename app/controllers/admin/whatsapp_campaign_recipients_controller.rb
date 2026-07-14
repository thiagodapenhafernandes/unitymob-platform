class Admin::WhatsappCampaignRecipientsController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_campaigns) }

  def index
    @sender_numbers = current_tenant.whatsapp_sender_numbers.ordered
    @selected_sender_number = @sender_numbers.find_by(id: params[:whatsapp_sender_number_id])
    @source = params[:source].presence || "spreadsheet"
    @conversion_status = params[:conversion_status].presence
    @query = params[:query].to_s.strip
    @recipients = filtered_recipients.paginate(page: params[:page], per_page: 40)
    @recipient_metrics = recipient_metrics
    @page_title = "Importados CSV"
  end

  private

  def filtered_recipients
    scope = visible_recipients_scope
      .includes(:whatsapp_campaign, :lead, :admin_user)
      .order(created_at: :desc)
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

  def visible_recipients_scope
    scope = current_tenant.whatsapp_campaign_recipients.joins(:whatsapp_campaign)
    owner_ids = visible_owner_ids(:whatsapp_campaigns)
    owner_ids.present? ? scope.where(whatsapp_campaigns: { created_by_id: owner_ids }) : scope
  end

  def recipient_metrics
    base_scope = visible_recipients_scope
    selected_scope = @selected_sender_number ? base_scope.where(whatsapp_campaigns: { whatsapp_sender_number_id: @selected_sender_number.id }) : base_scope

    {
      spreadsheet: base_scope.where(source: "spreadsheet").count,
      selected_spreadsheet: selected_scope.where(source: "spreadsheet").count,
      converted: selected_scope.where(conversion_status: "converted").count
    }
  end
end
