class LeadsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create] # Para facilitar testes AJAX se necessário, mas idealmente usar CSRF

  def whatsapp_url
    habitation = public_tenant.habitations.find_by(id: params[:property_id])
    routing = Whatsapp::SiteRouting.for_habitation(habitation, message: params[:message])

    render json: routing.slice(:capture_required, :whatsapp_url, :negotiation_type, :negotiation_label)
  end

  def create
    permitted = lead_params
    habitation = public_tenant.habitations.find_by(id: permitted[:property_id]) if permitted[:property_id].present?
    permitted[:property_id] = nil if permitted[:property_id].present? && habitation.blank?

    @lead = public_tenant.leads.new(permitted)
    @lead.source_url = request.referer
    apply_share_attribution(@lead)
    
    if @lead.save
      InterestIntelligence::SessionLinker.call(
        lead: @lead,
        token: cookies.signed[PublicNavigationSession::COOKIE_KEY]
      )

      habitation ||= public_tenant.habitations.find_by(id: @lead.property_id)
      business_type = lead_business_type(habitation)

      Seo::ConversionTracker.record!(
        event_type: "lead_created",
        request: request,
        lead: @lead,
        habitation: habitation,
        metadata: { origin: @lead.origin, lead_type: @lead.lead_type }
      )

      # Disparar Webhook
      # Disparar Webhook para todos os endpoints configurados
      WebhookService.send_form_data('whatsapp_lead', @lead.attributes.merge(
        property_code: habitation&.codigo,
        property_title: habitation&.display_title,
        property_url: habitation ? habitation_url(habitation) : nil,
        business_type: business_type,
        business_type_label: Whatsapp::SiteRouting::NEGOTIATION_TYPES[business_type],
        page_url: source_page_url,
        referrer_url: params.dig(:lead, :referrer_url),
        utm_source: params.dig(:lead, :utm_source),
        utm_medium: params.dig(:lead, :utm_medium),
        utm_campaign: params.dig(:lead, :utm_campaign),
        utm_term: params.dig(:lead, :utm_term),
        utm_content: params.dig(:lead, :utm_content),
        gclid: params.dig(:lead, :gclid),
        fbclid: params.dig(:lead, :fbclid),
        msclkid: params.dig(:lead, :msclkid)
      ).compact, request: request)

      # Send Emails (Async)
      LeadMailer.with(lead: @lead).new_lead_notification.deliver_later
      LeadMailer.with(lead: @lead).welcome_lead.deliver_later if @lead.email.present?

      render json: { 
        success: true, 
        whatsapp_url: @lead.whatsapp_url(message: lead_whatsapp_message)
      }
    else
      render json: { 
        success: false, 
        errors: @lead.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  private

  def lead_params
    params.require(:lead).permit(:name, :email, :phone, :property_id, :lead_type, :origin, :share_token)
  end

  def lead_business_type(habitation)
    requested_type = params.dig(:lead, :business_type).to_s
    return requested_type if Whatsapp::SiteRouting::NEGOTIATION_TYPES.key?(requested_type)

    habitation&.whatsapp_negotiation_type || "sale"
  end

  def source_page_url
    params.dig(:lead, :page_url).presence || request.referer
  end

  def lead_whatsapp_message
    params.dig(:lead, :whatsapp_message).to_s
  end

  def apply_share_attribution(lead)
    token = lead.share_token.to_s.strip.presence || cookies.signed[HabitationShareLink::COOKIE_KEY].to_s.strip
    return if token.blank? || lead.property_id.blank?

    share_link = HabitationShareLink.active.joins(:habitation).where(habitations: { tenant_id: public_tenant.id }).find_by(token: token, habitation_id: lead.property_id)
    return unless share_link

    lead.share_token = share_link.token
    lead.admin_user_id = share_link.admin_user_id
    lead.shared_by_admin_user_id = share_link.admin_user_id
    lead.origin = "Compartilhamento Corretor" if lead.origin.blank?
  end

end
