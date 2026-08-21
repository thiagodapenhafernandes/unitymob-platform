# frozen_string_literal: true

module Gateway
  module RouteResolver
    module_function

    def call(phone_number_id:, waba_id:)
      whatsapp(phone_number_id:, waba_id:)
    end

    def whatsapp(phone_number_id:, waba_id:)
      if phone_number_id.to_s.strip != ""
        route = WebhookRoute.find_by(provider: "whatsapp", phone_number_id: phone_number_id.to_s, active: true)
        return route if route
      end

      return if waba_id.to_s.strip == ""

      WebhookRoute.find_by(provider: "whatsapp", waba_id: waba_id.to_s, active: true)
    end

    def meta(page_id:, form_id: nil)
      page_id = page_id.to_s.strip
      form_id = form_id.to_s.strip
      return if page_id.empty?

      if form_id != ""
        route = WebhookRoute.find_by(provider: "meta", page_id:, form_id:, active: true)
        return route if route
      end

      WebhookRoute.find_by(provider: "meta", page_id:, form_id: [nil, ""], active: true)
    end
  end
end
