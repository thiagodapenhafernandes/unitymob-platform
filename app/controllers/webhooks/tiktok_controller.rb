class Webhooks::TiktokController < ActionController::Base
  skip_forgery_protection

  def create
    integration = TiktokIntegration.find_by(route_key: params[:route_key])
    return head :not_found unless integration
    secret = Tiktok::GatewayClient.forwarding_secret
    return head :unauthorized if secret.blank? || request.headers["X-Unitymob-Gateway-Provider"] != "tiktok"
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{integration.route_key}\n#{request.raw_post}")}"
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Unitymob-Gateway-Signature"].to_s)
    entry = JSON.parse(request.raw_post)
    unless entry.is_a?(Hash) && entry["id"].present? && entry["page_id"].present? && entry["changes"].is_a?(Array) &&
        entry["changes"].all? { |field| field.is_a?(Hash) && field["field"].is_a?(String) && field.key?("value") }
      return head :unprocessable_entity
    end
    return head :conflict unless integration.connected? && integration.selected_account_ids.include?(entry["advertiser_id"].to_s)
    TiktokLeadProcessingJob.perform_later(integration.id, entry)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
