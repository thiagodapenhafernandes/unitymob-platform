class Support::RegistrationsController < ActionController::Base
  protect_from_forgery with: :null_session

  def create
    return head :not_found unless SupportDesk.central?
    return head :payload_too_large if request.content_length.to_i > 4.kilobytes
    instance = request.headers['X-Support-Account'].to_s
    servers = JSON.parse(ENV.fetch('SUPPORT_TRUSTED_INSTANCES', '{}'))
    server = servers[instance]
    timestamp = request.headers['X-Support-Timestamp'].to_s
    return head :unauthorized unless server.is_a?(Hash) && server['secret'].to_s.length >= 32 && timestamp.match?(/\A\d{10}\z/) && (Time.current.to_i - timestamp.to_i).abs <= 300
    expected = Support::Transport.signature(server['secret'], timestamp, request.raw_post)
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers['X-Support-Signature'].to_s)
    data = JSON.parse(request.raw_post)
    return head :unprocessable_entity unless data.is_a?(Hash) && data['tenant_id'].to_s.match?(/\A[1-9]\d{0,18}\z/) && data['name'].is_a?(String) && data['name'].present? && data['name'].length <= 200
    uid = Support::Registration.uid(instance, data['tenant_id'])
    # Endpoint vem da infraestrutura confiável, nunca do payload do cliente (evita SSRF).
    account = Support::Account.create_or_find_by!(uid: uid) do |record|
      record.assign_attributes(name: data['name'], endpoint: server.fetch('endpoint'), secret: Support::Registration.secret(server['secret'], uid))
    end
    account.with_lock do
      # Repetir o registro não reativa uma conta bloqueada pelo administrador.
      account.update!(name: data['name'], endpoint: server.fetch('endpoint'))
    end
    render json: { uid: account.uid }
  rescue JSON::ParserError, KeyError, ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end
end
