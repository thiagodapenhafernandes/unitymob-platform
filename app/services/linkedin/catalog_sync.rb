module Linkedin
  class CatalogSync
    def self.call(integration, client: Client.new(integration.access_token))
      accounts = client.accounts.map { |row| { "id" => Client.id(row.fetch("id")), "name" => row.fetch("name") } }
      catalog = {}
      errors = []
      accounts.select { |account| integration.selected_account_ids.include?(account["id"]) }.each do |account|
        forms = client.forms(account["id"]).index_by { |form| form.fetch("id").to_s }
        creatives = client.creatives(account["id"]).group_by { |creative| Client.id(creative["campaign"]) }
        client.campaigns(account["id"]).each do |campaign|
          id = Client.id(campaign.fetch("id"))
          linked_forms = Array(creatives[id]).filter_map do |creative|
            destination = creative.dig("leadgenCallToAction", "destination") || creative.dig("leadgenCallToAction", "adFormUrn")
            form = forms[Client.id(destination)]
            next unless form
            { "id" => form.fetch("id").to_s, "name" => form.fetch("name") }
          end.uniq { |form| form["id"] }
          next if linked_forms.empty?
          catalog[id] = { "name" => campaign.fetch("name"), "account_id" => account["id"], "account_name" => account["name"], "forms" => linked_forms }
        end
      rescue Client::Error => error
        errors << error.message
      end
      integration.update!(ad_accounts: accounts, catalog: catalog, catalog_synced_at: errors.empty? ? Time.current : nil)
      errors
    end
  end
end
