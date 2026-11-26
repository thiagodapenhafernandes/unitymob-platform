class Webhooks::ChavesNaMaoController < ActionController::Base
  skip_forgery_protection

  def create
    connection = ChavesNaMaoConnection.find_by(route_key: params[:route_key])
    return head :not_found unless connection
    return head :conflict unless connection.receiving?
    return head :unauthorized unless connection.authenticated?(request.headers["Authorization"])
    return head :payload_too_large if request.raw_post.bytesize > 64.kilobytes

    entry = JSON.parse(request.raw_post)
    return head :unprocessable_entity unless entry.is_a?(Hash) && entry.present?

    digest = Digest::SHA256.hexdigest(request.raw_post)
    if connection.operational?
      return head :unprocessable_entity unless entry["id"].is_a?(String) && entry["id"].present? && entry["id"].bytesize <= 255

      receipt = connection.chaves_na_mao_lead_receipts.create_or_find_by!(event_id: entry["id"]) do |record|
        record.assign_attributes(payload_digest: Digest::SHA256.hexdigest("operational:#{request.raw_post}"), payload: request.raw_post, received_at: Time.current, status: "pending")
      end
      ChavesNaMaoLeadProcessingJob.perform_later(receipt.id) if receipt.status == "pending"
    else
      connection.chaves_na_mao_lead_receipts.create_or_find_by!(payload_digest: digest) do |record|
        record.assign_attributes(payload: request.raw_post, received_at: Time.current)
      end
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
