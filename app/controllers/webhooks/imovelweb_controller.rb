class Webhooks::ImovelwebController < ActionController::Base
  skip_forgery_protection

  def create
    connection = ImovelwebConnection.find_by(route_key: params[:route_key])
    return head :not_found unless connection
    secret = Imovelweb::GatewayClient.forwarding_secret
    return head :unauthorized if secret.to_s.length < 32 || request.headers["X-Unitymob-Gateway-Provider"] != "imovelweb"
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{connection.route_key}\n#{request.raw_post}")}"
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Unitymob-Gateway-Signature"].to_s)
    return head :conflict unless connection.receiving?
    return head :payload_too_large if request.raw_post.bytesize > 64.kilobytes
    entry = JSON.parse(request.raw_post)
    return head :unprocessable_entity unless Imovelweb::ReceiveLead.valid_payload?(entry)
    return head :conflict unless entry["client_code"] == connection.client_code && entry["environment"] == connection.environment

    receipt = connection.imovelweb_lead_receipts.create_or_find_by!(event_id: entry.fetch("event_id")) do |record|
      record.assign_attributes(event_type: entry.fetch("event_type"), payload: entry.to_json, received_at: Time.current)
    end
    if receipt.status == "pending" && !ImovelwebLeadProcessingJob.perform_later(receipt.id)
      return head :service_unavailable
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
