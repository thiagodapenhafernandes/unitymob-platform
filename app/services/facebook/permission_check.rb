module Facebook
  class PermissionCheck
    PERMISSIONS = {
      "pages_show_list" => ["Páginas", "Localizar as páginas que você administra."],
      "pages_read_engagement" => ["Dados das páginas", "Ler informações das páginas conectadas."],
      "pages_manage_metadata" => ["Webhooks", "Configurar inscrições para receber eventos das páginas."],
      "leads_retrieval" => ["Formulários", "Consultar os cadastros enviados pelos formulários Meta."],
      "instagram_basic" => ["Perfil Instagram", "Identificar o Instagram profissional vinculado à página."],
      "instagram_manage_messages" => ["Direct", "Acessar mensagens do Instagram profissional."],
      "ads_management" => ["Anúncios", "Permissão solicitada pela conexão atual para acessar anúncios; ads_read também permite o enriquecimento de campanhas."]
    }.freeze

    def self.call(integration)
      return { error: "Conexão expirada. Atualize a autorização com o Facebook." } if integration.expired? || integration.access_token.blank?

      graph = Koala::Facebook::API.new(integration.access_token)
      response = graph.get_connections("me", "permissions")
      granted = {}
      while response.present?
        response.each { |row| granted[row.fetch("permission")] = row.fetch("status") }
        response = response.respond_to?(:next_page) ? response.next_page : nil
      end
      { checked_at: Time.current, permissions: PERMISSIONS.map do |key, (label, description)|
        status = granted[key]
        status = "granted" if key == "ads_management" && granted["ads_read"] == "granted"
        { key: key, label: label, description: description, status: status || "missing" }
      end }
    rescue Koala::Facebook::APIError => error
      { error: error.fb_error_code.to_i == 190 ? "A Meta recusou o token. Atualize a autorização com o Facebook." : "Não foi possível consultar as permissões na Meta. Tente novamente; isso não significa que elas foram recusadas." }
    rescue Faraday::Error, Timeout::Error, SocketError
      { error: "A consulta à Meta está indisponível. Tente novamente em instantes." }
    end
  end
end
