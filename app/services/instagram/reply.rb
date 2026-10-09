module Instagram
  # Resposta do corretor a uma conversa do Instagram Direct pela API da Meta.
  # Regras: página vinculada e ativa na conta, janela de 24h da última
  # mensagem do cliente aberta e texto de até 1000 caracteres.
  class Reply
    class Error < StandardError; end

    WINDOW = 24.hours
    MAX_CHARS = 1000

    def self.call(lead:, body:, admin_user:)
      new(lead:, body:, admin_user:).call
    end

    def self.window_open?(lead)
      last_inbound_at(lead).present? && last_inbound_at(lead) >= WINDOW.ago
    end

    def self.last_inbound_at(lead)
      lead.instagram_messages.inbound.maximum(:occurred_at)
    end

    def initialize(lead:, body:, admin_user:)
      @lead = lead
      @body = body.to_s.strip
      @admin_user = admin_user
    end

    def call
      page = reply_page
      raise Error, "Lead sem conversa do Instagram." if @lead.instagram_account_id.blank? || @lead.instagram_scoped_id.blank?
      raise Error, "Página do Instagram desconectada. Verifique a integração Meta." if page.blank? || page.access_token.blank?
      raise Error, "Digite a mensagem antes de enviar." if @body.blank?
      raise Error, "Mensagem limitada a #{MAX_CHARS} caracteres." if @body.length > MAX_CHARS
      raise Error, "Janela de 24h encerrada. Aguarde uma nova mensagem do cliente." unless self.class.window_open?(@lead)

      response = Koala::Facebook::API.new(page.access_token).put_connections(
        @lead.instagram_account_id,
        "messages",
        recipient: { id: @lead.instagram_scoped_id }.to_json,
        messaging_type: "RESPONSE",
        message: { text: @body }.to_json
      )
      message_id = response.is_a?(Hash) ? response["message_id"].presence : nil

      @lead.instagram_messages.create!(
        message_id: message_id.presence || "out-#{SecureRandom.uuid}",
        body: @body,
        direction: "outbound",
        occurred_at: Time.current,
        sent_by_admin_user: @admin_user,
        context: { "by" => @admin_user&.name }.compact
      ).tap do |message|
        LeadActivity.log!(lead: @lead, kind: "instagram_out", metadata: {
          "by" => @admin_user&.name, "preview" => @body.truncate(140)
        }.compact)
      end
    rescue Koala::Facebook::APIError => error
      raise Error, sync_failure_message(error)
    end

    private

    def reply_page
      MetaFacebookPage.joins(:user_meta_integration)
        .where(user_meta_integrations: { tenant_id: @lead.tenant_id })
        .find_by(instagram_id: @lead.instagram_account_id, instagram_enabled: true, active: true)
    end

    def sync_failure_message(error)
      case error.fb_error_code.to_i
      when 190 then "A Meta recusou o token. Renove a autorização da integração."
      when 10, 200, 230 then "Sem permissão de mensagens no Instagram. Confira o acesso da página."
      else "A Meta recusou o envio. Tente novamente em instantes."
      end
    end
  end
end
