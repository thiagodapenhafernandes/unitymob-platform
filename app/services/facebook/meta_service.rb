module Facebook
  class MetaService
    class MetaAPIError < StandardError; end

    def initialize(access_token)
      @graph = Koala::Facebook::API.new(access_token)
    end

    def get_user_pages
      all_pages = []
      response = @graph.get_connections("me", "accounts", fields: "id,name,access_token,category")
      while response.present?
        all_pages.concat(response)
        response = response.next_page
      end
      all_pages
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "MetaService Error: Failed to get Facebook pages: #{e.message}"
      raise MetaAPIError.new("Não foi possível obter suas páginas do Facebook.")
    end

    def get_page_lead_forms(page_id, page_access_token)
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
      page_graph = Koala::Facebook::API.new(page_access_token)
      result = page_graph.put_connections(
        page_id,
        "subscribed_apps",
        subscribed_fields: subscribed_fields.join(",")
      )
      Rails.logger.info "MetaService: Página #{page_id} subscrita para webhooks."
      result
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "MetaService Error: Failed to subscribe page #{page_id}: #{e.message}"
      raise MetaAPIError.new("Não foi possível subscrever a página para webhooks.")
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
  end
end
