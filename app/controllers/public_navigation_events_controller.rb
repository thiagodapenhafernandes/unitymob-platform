class PublicNavigationEventsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

  def create
    settings = InterestIntelligence::Settings.current
    unless settings.enabled?
      render json: { ok: false, disabled: true }
      return
    end

    if settings.enabled_value?("requires_public_tracking_consent") && cookies[:unitymob_interest_consent] != "accepted"
      render json: { ok: false, consent_required: true }
      return
    end

    normalized_event_name = event_name
    unless normalized_event_name
      render json: { ok: false }, status: :unprocessable_content
      return
    end

    session = public_navigation_session
    habitation = find_habitation
    event = session.events.create!(
      lead: session.lead,
      habitation: habitation,
      name: normalized_event_name,
      path: navigation_event_params[:path].presence || request.referer,
      duration_seconds: navigation_event_params[:duration_seconds],
      occurred_at: Time.current,
      search_params: search_params_payload,
      property_snapshot: property_snapshot_for(habitation).merge(property_snapshot_payload),
      metadata: metadata_payload
    )

    render json: { ok: true, token: session.token, event_id: event.id }
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[public navigation] #{e.class}: #{e.message}")
    render json: { ok: false }, status: :unprocessable_content
  end

  private

  def public_navigation_session
    token = cookies.signed[PublicNavigationSession::COOKIE_KEY].to_s
    session = PublicNavigationSession.find_or_create_for_token(token, request: request)

    cookies.signed[PublicNavigationSession::COOKIE_KEY] = {
      value: session.token,
      expires: 6.months.from_now,
      same_site: :lax
    }

    session
  end

  def navigation_event_params
    params.require(:navigation_event).permit(:name, :path, :habitation_id, :duration_seconds)
  end

  def event_name
    name = navigation_event_params[:name].to_s.presence || "page_view"
    allowed = PublicNavigationEvent::PROPERTY_EVENT_NAMES + PublicNavigationEvent::SEARCH_EVENT_NAMES
    allowed.include?(name) ? name : nil
  end

  def find_habitation
    id = navigation_event_params[:habitation_id].to_s
    return nil if id.blank?

    public_habitations.active.find_by(id: id)
  end

  def search_params_payload
    params.fetch(:navigation_event, {}).fetch(:search_params, {}).to_unsafe_h
  rescue NoMethodError
    {}
  end

  def property_snapshot_payload
    params.fetch(:navigation_event, {}).fetch(:property_snapshot, {}).to_unsafe_h
  rescue NoMethodError
    {}
  end

  def metadata_payload
    raw = params.fetch(:navigation_event, {}).fetch(:metadata, {})
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : {}
  end

  def property_snapshot_for(habitation)
    return {} unless habitation

    {
      city: habitation_location(habitation, :cidade),
      neighborhood: habitation_location(habitation, :bairro),
      category: habitation.categoria,
      bedrooms: habitation.dormitorios_qtd,
      price_cents: habitation.valor_venda_cents.presence || habitation.valor_locacao_cents,
      codigo: habitation.codigo
    }.compact
  end

  def habitation_location(habitation, attribute)
    habitation.public_send(attribute).presence || habitation.read_attribute(attribute).presence
  end
end
