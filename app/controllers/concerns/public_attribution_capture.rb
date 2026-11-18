module PublicAttributionCapture
  private

  def capture_public_attribution(fields:, page_url:)
    page_url = nil unless page_url.is_a?(String)
    keys = Leads::Attribution::TRACKING_KEYS
    permitted = ->(value) do
      value = ActionController::Parameters.new unless value.is_a?(ActionController::Parameters)
      value.permit(*keys, first_touch: keys, conversion_touch: keys).to_h
    end
    raw = attribution_url_parameters(page_url.presence || request.referer).slice(*keys)
      .merge(request.query_parameters.slice(*keys))
      .merge(permitted.call(fields)).merge(permitted.call(params[:attribution]))
    raw["landing_url"] ||= page_url.presence || request.referer
    raw["referrer_url"] ||= request.referer
    Leads::Attribution.capture(raw: raw, request: request)
  end

  def attribution_url_parameters(url)
    return {} unless url.is_a?(String)

    URI.decode_www_form(URI.parse(url.to_s.first(4096)).query.to_s).to_h
  rescue URI::InvalidURIError, ArgumentError
    {}
  end
end
