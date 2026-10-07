class LinkedinSyncJob < ApplicationJob
  queue_as :sync
  retry_on Linkedin::Client::Error, wait: :polynomially_longer, attempts: 5

  def perform(integration_id, refresh_catalog: false)
    integration = LinkedinIntegration.find_by(id: integration_id)
    return unless integration

    failure = nil
    Current.set(tenant: integration.tenant) do
      # ponytail: serialize per connection during HTTP; split catalog/receiving if volume requires it.
      integration.with_lock do
        return unless integration.connected?
        client = Linkedin::Client.new(integration.access_token)
        errors = []
        if refresh_catalog || integration.catalog_synced_at.nil? || integration.catalog_synced_at < 15.minutes.ago
          errors.concat(Linkedin::CatalogSync.call(integration, client: client))
        end
        cursors = integration.account_cursors.deep_dup
        integration.selected_account_ids.each do |account_id|
          next unless integration.ad_accounts.any? { |account| account["id"] == account_id }
          cursor = cursors.fetch(account_id)
          to = (Time.current.to_f * 1000).to_i
          # Overlap catches delayed availability; receipts prevent duplicate distribution.
          from = [cursor.fetch("since").to_i, cursor.fetch("last", cursor["since"]).to_i - 10.minutes.in_milliseconds].max
          client.responses(account_id, from: from, to: to).each do |response|
            next if response.fetch("submittedAt").to_i < cursor.fetch("since").to_i
            Linkedin::ReceiveLead.call(integration, response, client: client)
          end
          cursor["last"] = to
        rescue Linkedin::Client::Error => error
          errors << error.message
        end
        unavailable = integration.selected_account_ids - integration.ad_accounts.pluck("id")
        errors << "Uma conta de anúncios selecionada não está mais acessível. Atualize o acesso ou revise a seleção de contas." if unavailable.any?
        failure = errors.uniq.join(" ").presence
        integration.update!(account_cursors: cursors, last_synced_at: errors.empty? ? Time.current : integration.last_synced_at, last_error: failure)
      end
    end
    raise Linkedin::Client::Error, failure if failure
  rescue StandardError => error
    message = error.is_a?(Linkedin::Client::Error) ? error.message : "Não foi possível atualizar o LinkedIn. Tente novamente; se persistir, contate o suporte."
    integration&.update_columns(last_error: message)
    Rails.logger.warn("[LinkedinSync] integration_id=#{integration_id} error=#{error.class}")
    raise
  end
end
