require 'active_support/message_encryptor'
require 'digest'

module Gateway
  module ImovelwebRejectedCallback
    module_function

    def cipher(environment)
      key = Digest::SHA256.digest("imovelweb-rejected:#{ENV.fetch("IMOVELWEB_#{environment.upcase}_CALLBACK_TOKEN")}")
      ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
    end

    def record(environment:, raw:, reason:)
      key = Digest::SHA256.hexdigest("imovelweb-rejected:#{environment}:#{raw}")
      # No route or queue: a rejected body can only be recovered after validation.
      WebhookEvent.create_or_find_by!(delivery_key: key) do |event|
        event.assign_attributes(provider: 'imovelweb', event_type: 'rejected_callback', status: 'failed',
          received_at: Time.now, last_error: reason,
          payload: { environment: environment, encrypted_body: cipher(environment).encrypt_and_sign(raw) })
      end
    end
  end
end
