module Instagram
  class Connection
    class Error < StandardError; end

    def self.discover(page)
      graph = Koala::Facebook::API.new(page.user_meta_integration.access_token)
      data = graph.get_object(page.page_id, fields: "instagram_business_account{id,username}")
      profile = data["instagram_business_account"] || {}
      raise Error, "Desative o perfil atual antes de trocar seu vínculo." if page.instagram_enabled? && profile["id"] != page.instagram_id
      page.update!(instagram_id: profile["id"], instagram_username: profile["username"])
    end

    def self.activate(page)
      raise Error, "Descubra o perfil e atualize a autorização da página antes de ativar." if page.instagram_id.blank? || page.access_token.blank?
      discover(page)
      raise Error, "Nenhum Instagram profissional acessível nesta página." if page.instagram_id.blank?
      page.with_lock do
        page.update!(instagram_enabled: true) # Unique index prevents ambiguous routing.
        if Meta::WebhookConfiguration.gateway?
          route_page = Struct.new(:page_id, :active?).new(page.instagram_id, true)
          result = Meta::WebhookGatewayClient.new(page: route_page, tenant: page.user_meta_integration.tenant).register_route
          raise Error, "Não foi possível configurar a rota no gateway." unless result.ok?
        end
        Facebook::MetaService.new(page.access_token).subscribe_page_to_app(page.page_id, page.access_token, subscribed_fields: ["messages"])
        apps = Koala::Facebook::API.new(page.access_token).get_connections(page.page_id, "subscribed_apps", fields: "id,subscribed_fields")
        confirmed = false
        while apps.present?
          confirmed ||= apps.any? { |app| app["id"].to_s == ENV["FACEBOOK_APP_ID"].to_s && Array(app["subscribed_fields"]).include?("messages") }
          apps = apps.respond_to?(:next_page) ? apps.next_page : nil
        end
        raise Error, "A Meta ainda não confirmou a inscrição de mensagens." unless confirmed
      end
    end
  end
end
