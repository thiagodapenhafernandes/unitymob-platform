# frozen_string_literal: true

module Gateway
  module RouteResolver
    module_function

    def call(phone_number_id:, waba_id:)
      if phone_number_id.to_s.strip != ""
        route = WebhookRoute.find_by(provider: "whatsapp", phone_number_id: phone_number_id.to_s, active: true)
        return route if route
      end

      return if waba_id.to_s.strip == ""

      WebhookRoute.find_by(provider: "whatsapp", waba_id: waba_id.to_s, active: true)
    end
  end
end
