module Meta
  module WebhookConfiguration
    MODES = %w[gateway direct].freeze
    DEFAULT_MODE = "direct".freeze

    module_function

    def mode
      ENV["META_LEADS_WEBHOOK_MODE"].to_s.presence_in(MODES) || DEFAULT_MODE
    end

    def gateway?
      mode == "gateway"
    end

    def direct?
      mode == "direct"
    end

    def callback_url
      gateway? ? WebhookGatewayClient.public_webhook_url : direct_webhook_url
    end

    def verify_token
      WebhookGatewayClient.verify_token
    end

    def label
      gateway? ? "Gateway Unitymob" : "App próprio"
    end

    def description
      if gateway?
        "Use quando a imobiliária não tiver app Meta próprio preparado. A Meta entrega no gateway central da Unitymob, que roteia por página/formulário para o CRM correto."
      else
        "Use quando a imobiliária tiver app Meta próprio. A Meta entrega direto neste CRM, preservando o fluxo legado."
      end
    end

    def direct_webhook_url
      ENV["META_LEADS_DIRECT_WEBHOOK_PUBLIC_URL"].presence ||
        ENV["APP_HOST"].presence&.delete_suffix("/")&.then { |host| "#{host}/webhooks/meta" }
    end
  end
end
