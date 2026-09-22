module Whatsapp
  # Conecta um número de disparo à Meta de ponta a ponta: valida o Phone Number ID com o token,
  # inscreve o app na WABA (sem isso a Meta não envia webhooks), confere a inscrição e registra a rota no gateway.
  class SenderNumberConnector
    Result = Struct.new(:skipped, :warnings, :subscribed_apps, :phone, keyword_init: true) do
      def skipped? = skipped
      def success? = !skipped && warnings.empty?
    end

    def self.call(sender_number, tenant:, target_url:)
      new(sender_number, tenant:, target_url:).call
    end

    def initialize(sender_number, tenant:, target_url:)
      @sender = sender_number
      @tenant = tenant
      @target_url = target_url
    end

    def call
      warnings = []
      meta_ready = sender.messaging_ready? && sender.waba_id.present?
      apps = []
      phone = nil

      if meta_ready
        client = Whatsapp::CloudClient.new(sender)
        phone = client.phone_info
        if phone[:ok]
          refresh_from(phone[:data])
        else
          warnings << "Phone Number ID não validado na Meta com o token atual: #{phone[:error].presence || 'sem detalhes'}"
        end

        subscription = client.subscribe_app
        warnings << "Não foi possível inscrever o app na WABA #{sender.waba_id}: #{subscription[:error].presence || 'sem detalhes'}" unless subscription[:ok]

        apps = Array(client.subscribed_apps.dig(:data, "data"))
        warnings << "A WABA #{sender.waba_id} continua sem app inscrito: o número não receberá mensagens." if subscription[:ok] && apps.empty?
      end

      gateway = Whatsapp::WebhookGatewayClient.new(integration: sender, tenant: tenant, target_url: target_url).register_route
      warnings << "Não foi possível registrar a rota no gateway de webhooks: #{gateway.error.presence || 'sem detalhes'}" unless gateway.ok? || gateway.skipped?

      Result.new(skipped: !meta_ready, warnings: warnings, subscribed_apps: apps.filter_map { |app| app.dig("whatsapp_business_api_data", "name") }, phone: phone&.dig(:data))
    end

    private

    attr_reader :sender, :tenant, :target_url

    def refresh_from(data)
      attrs = { verified_name: data["verified_name"], quality_rating: data["quality_rating"] }.compact_blank
      sender.update_columns(attrs.merge(updated_at: Time.current)) if attrs.any?
    end
  end
end
