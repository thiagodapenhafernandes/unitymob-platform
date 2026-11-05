# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :oauth_handoff, :oauth_ticket, :nonce,
  :reporting_credentials,
  /\A(?:code|auth_code)\z/,
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,
  :feed_token, :webhook_secret, :account_id, :publisher_id,
  :whatsapp, :entry, :changes, :contacts, :messages, :statuses,
  :image, :verifier, :challenge, :contact_phone, :expected_email,
  /\A(?:note\.body|lead\.(?:name|email|phone)|task\.title)\z/
]

# Only the normalized Imovelweb callback envelope; do not expose contact data in request logs.
Rails.application.config.filter_parameters << lambda do |key, value, parameters|
  next unless parameters

  if parameters["event_type"].in?(%w[CONTACTO CONTACTO_MENSAJE]) && parameters.key?("client_code") &&
      %w[name email phone message].include?(key) && value.is_a?(String)
    value.replace("[FILTERED]")
  end
end
