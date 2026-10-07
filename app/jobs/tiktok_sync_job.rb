class TiktokSyncJob < ApplicationJob
  queue_as :sync
  retry_on Tiktok::Client::Error, wait: :polynomially_longer, attempts: 5

  def perform(integration_id)
    integration = TiktokIntegration.find_by(id: integration_id)
    return unless integration
    Current.set(tenant: integration.tenant) do
      # ponytail: serialize network operations per connection; split jobs if volume requires it.
      integration.with_lock do
        return unless integration.connected?
        client = Tiktok::Client.new(integration.access_token)
        Tiktok::GatewayClient.pause_unselected!(integration)
        accounts = client.accounts
        known = accounts.pluck("advertiser_id").map(&:to_s)
        remote = client.subscriptions
        subscriptions = integration.subscriptions.deep_dup
        owned = remote.select { |row| Tiktok::GatewayClient.owns_callback?(row["callback_url"], integration) }
        owned.each do |row|
          id = row.fetch("subscription_detail")["advertiser_id"].to_s
          next if integration.selected_account_ids.include?(id) && row["callback_url"] == Tiktok::GatewayClient.callback_url(integration)
          client.unsubscribe(row.fetch("subscription_id"))
          subscriptions.delete(id)
        end
        subscriptions.slice!(*integration.selected_account_ids)
        integration.update!(subscriptions: subscriptions)
        catalog = {}
        integration.selected_account_ids.each do |id|
          unless known.include?(id)
            Tiktok::GatewayClient.sync!(integration, id, active: false)
            raise Tiktok::Client::Error, "Um anunciante selecionado não está mais autorizado. Reconecte ou revise a seleção."
          end
          Tiktok::GatewayClient.sync!(integration, id, active: true)
          existing = owned.find do |row|
            detail = row.fetch("subscription_detail")
            row["callback_url"] == Tiktok::GatewayClient.callback_url(integration) && detail["advertiser_id"].to_s == id &&
              detail["page_id"].blank? && detail["lead_source"].to_s.in?(["", "INSTANT_FORM"])
          end
          subscriptions[id] = existing ? existing.fetch("subscription_id").to_s : client.subscribe(id, integration: integration)
          integration.update!(subscriptions: subscriptions)
          account = accounts.find { |row| row["advertiser_id"].to_s == id }
          catalog[id] = { "name" => account.fetch("advertiser_name"), "forms" => client.forms(id).map { |form| { "id" => form.fetch("page_id").to_s, "name" => form.fetch("title") } } }
        end
        integration.update!(ad_accounts: accounts, catalog: catalog, last_synced_at: Time.current, last_error: nil)
      end
    end
  rescue Tiktok::Client::Error => error
    integration&.update_columns(last_error: error.message)
    raise
  end
end
