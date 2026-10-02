module Facebook
  class MetaService
    class MetaAPIError < StandardError; end

    def initialize(access_token)
      @graph = Koala::Facebook::API.new(access_token)
    end

    def get_user_pages
      pages = paginated_connections(@graph, "me", "accounts", fields: page_fields)
      dedupe_pages(pages)
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "MetaService Error: Failed to get Facebook pages: #{e.message}"
      raise MetaAPIError.new("Não foi possível obter suas páginas do Facebook.")
    end

    def get_page_lead_forms(page_id, page_access_token)
      raise MetaAPIError, "Página sem autorização. Atualize a conexão Meta selecionando esta página." if page_access_token.blank?
      page_graph = Koala::Facebook::API.new(page_access_token)
      all_forms = []
      response = page_graph.get_connections(page_id, "leadgen_forms", fields: "id,name,status,created_time")
      while response.present?
        all_forms.concat(response)
        response = response.next_page
      end
      all_forms
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "MetaService Error: Failed to get lead forms for page #{page_id}: #{e.message}"
      raise MetaAPIError.new("Não foi possível obter os formulários de leads para a página #{page_id}.")
    end

    def subscribe_page_to_app(page_id, page_access_token, subscribed_fields: [ "leadgen" ])
      raise MetaAPIError, "Página sem autorização. Atualize a conexão Meta selecionando esta página." if page_access_token.blank?
      page_graph = Koala::Facebook::API.new(page_access_token)
      raise MetaAPIError, "Configure o App ID da Meta antes de assinar eventos." if ENV["FACEBOOK_APP_ID"].blank?
      subscriptions = page_graph.get_connections(page_id, "subscribed_apps", fields: "id,subscribed_fields")
      all_subscriptions = []
      while subscriptions.present?
        all_subscriptions.concat(subscriptions)
        subscriptions = subscriptions.respond_to?(:next_page) ? subscriptions.next_page : nil
      end
      existing = all_subscriptions.find { |app| app["id"].to_s == ENV["FACEBOOK_APP_ID"].to_s }
      fields = (Array(existing&.dig("subscribed_fields")) + subscribed_fields).uniq
      result = page_graph.put_connections(
        page_id,
        "subscribed_apps",
        subscribed_fields: fields.join(",")
      )
      raise MetaAPIError, "A Meta não confirmou a inscrição." unless result == true || result.is_a?(Hash) && result["success"] == true
      Rails.logger.info "MetaService: Página #{page_id} subscrita para webhooks."
      result
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "MetaService Error: Failed to subscribe page #{page_id}: #{e.message}"
      raise MetaAPIError.new("Não foi possível subscrever a página para webhooks.")
    end

    def ad_accounts(all: false, page_ids: nil)
      return paginated_connections(@graph, "me", "adaccounts", fields: "account_id,name").uniq { |account| account["account_id"] } if all

      return [] if page_ids == []

      pages = paginated_connections(@graph, "me", "accounts", fields: "id,business")
      pages.select! { |page| page_ids.include?(page["id"].to_s) } unless page_ids.nil?
      business_ids = pages.filter_map { |page| page.dig("business", "id") }.uniq
      business_ids.flat_map do |id|
        %w[owned_ad_accounts client_ad_accounts].flat_map do |edge|
          paginated_connections(@graph, id, edge, fields: "account_id,name")
        end
      end.uniq { |account| account["account_id"] }
    end

    def ad_account(account_id)
      @graph.get_object("act_#{account_id}", fields: "account_id,name")
    end

    def ad_details(ad_id)
      @graph.get_object(ad_id, fields: "id,name,account_id,campaign{id,name},adset{id,name}")
    end

    def campaign_details(campaign_id)
      @graph.get_object(campaign_id, fields: "id,name,account_id")
    end

    def get_lead_details(lead_id)
      @graph.get_object(lead_id)
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "MetaService Error: Failed to get lead details #{lead_id}: #{e.message}"
      raise MetaAPIError.new("Não foi possível buscar detalhes do lead #{lead_id}.")
    end

    def self.exchange_access_token(short_lived_token)
      oauth = Koala::Facebook::OAuth.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_APP_SECRET"])
      oauth.exchange_access_token_info(short_lived_token)
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "MetaService Error: Failed to exchange access token: #{e.message}"
      nil
    end

    private

    def page_fields
      "id,name,access_token,category"
    end

    def paginated_connections(graph, object, connection, **options)
      records = []
      response = graph.get_connections(object, connection, **options)

      while response.present?
        records.concat(response)
        response = response.respond_to?(:next_page) ? response.next_page : nil
      end

      records
    end

    def dedupe_pages(pages)
      pages.each_with_object({}) do |page, result|
        page_id = object_value(page, "id").to_s
        next if page_id.blank?

        result[page_id] ||= page
      end.values
    end

    def object_value(object, key)
      return object[key] if object.respond_to?(:[])

      object.public_send(key) if object.respond_to?(key)
    end
  end
end
