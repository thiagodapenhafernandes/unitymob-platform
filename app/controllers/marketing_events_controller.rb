class MarketingEventsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

  def create
    return head :accepted unless lgpd_consent_accepted?

    event_type = params[:event_type].presence_in(SeoConversionEvent::EVENT_TYPES.keys) || "campaign_click"
    campaign = public_tenant.marketing_campaigns.find_by(id: params[:marketing_campaign_id])
    habitation = public_tenant.habitations.find_by(id: params[:habitation_id])

    event = Seo::ConversionTracker.record!(
      event_type: event_type,
      request: request,
      habitation: habitation,
      metadata: metadata_payload.merge(target_url: params[:target_url])
    )

    campaign ||= event&.marketing_campaign
    campaign&.register_click! if click_event?(event_type)

    head :accepted
  end

  private

  def metadata_payload
    params.permit(:placement, :label, :target_url, :page_url, :component).to_h
  end

  def click_event?(event_type)
    %w[campaign_click footer_click property_card_click whatsapp_click cta_click share_click].include?(event_type.to_s)
  end

end
