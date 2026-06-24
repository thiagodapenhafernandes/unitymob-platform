module Leads
  # Motor único de "link seguro" das notificações de distribuição.
  #
  # Decide, por canal, se o contato do lead é mascarado atrás de um link
  # /s/:token (que valida expiração, registra o acesso e marca o lead como
  # atendido dentro do prazo) ou se o dado vai direto. Gateado pelo LeadSetting:
  # o master `secure_links_enabled` E o toggle do canal precisam estar ligados,
  # e o lead precisa estar persistido (token referencia um registro real).
  #
  # Usado por WhatsApp, e-mail e push para falar a mesma língua.
  class ContactLinks
    CHANNEL_FLAGS = {
      whatsapp: :secure_link_whatsapp?,
      email:    :secure_link_email?,
      push:     :secure_link_push?
    }.freeze

    def initialize(lead, corretor, setting: LeadSetting.instance)
      @lead = lead
      @corretor = corretor
      @setting = setting
    end

    # O canal vai usar link seguro? Master ligado + lead salvo + canal ligado.
    def secure?(channel)
      return false unless @setting.secure_links_enabled? && @lead.persisted?

      @setting.public_send(CHANNEL_FLAGS.fetch(channel))
    end

    # URL absoluta /s/:token para a ação (phone/email/view/attend), reaproveitando
    # ou criando o SecureLink do lead para este corretor.
    def url(action)
      SecureLink.link_for(
        @lead, action,
        expiry_days: @setting.secure_link_expiry_days,
        issued_to: @corretor
      ).full_url
    end
  end
end
