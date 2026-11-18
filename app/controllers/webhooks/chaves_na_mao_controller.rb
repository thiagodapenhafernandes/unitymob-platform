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

    # Captura de homologação: nenhum evento cria lead, distribui ou notifica.
    connection.chaves_na_mao_lead_receipts.create_or_find_by!(payload_digest: Digest::SHA256.hexdigest(request.raw_post)) do |receipt|
      receipt.assign_attributes(payload: request.raw_post, received_at: Time.current)
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
