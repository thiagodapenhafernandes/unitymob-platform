module ExternalLeadMigration
  class WebhookSubscriptionService
    HOOK_ACTIONS = %w[on_create_lead on_update_lead on_close_lead].freeze

    def self.subscribe!(integration:, hook_url:)
      new(integration:).subscribe!(hook_url:)
    end

    def self.unsubscribe!(integration:, deactivate: true)
      new(integration:).unsubscribe!(deactivate:)
    end

    def initialize(integration:)
      @integration = integration
    end

    def subscribe!(hook_url:)
      client = Client.new(token: integration.access_token)
      HOOK_ACTIONS.each do |action|
        client.subscribe!(hook_action: action, hook_url: hook_url)
      end
      integration.update!(
        webhook_listening_enabled: true,
        webhook_url: hook_url,
        subscribed_at: Time.current,
        unsubscribed_at: nil,
        status: "connected",
        sync_message: "Webhooks externos assinados: criação, atualização e fechamento.",
        last_error_message: nil
      )
    end

    def unsubscribe!(deactivate: true)
      Client.new(token: integration.access_token).unsubscribe!
      attrs = {
        webhook_listening_enabled: false,
        webhook_url: nil,
        subscribed_at: nil,
        unsubscribed_at: Time.current,
        sync_message: "Escuta de novos leads desativada e webhook externo cancelado."
      }
      attrs.merge!(
        enabled: false,
        status: "inactive",
        deactivated_at: Time.current,
        sync_message: "Integração externa inativada e webhook cancelado."
      ) if deactivate
      integration.update!(attrs)
    end

    private

    attr_reader :integration
  end
end
