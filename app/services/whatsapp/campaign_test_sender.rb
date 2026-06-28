module Whatsapp
  class CampaignTestSender
    def self.call(template:, phone:, variables:, sender_number: nil, admin_user: nil)
      new(template, phone, variables, sender_number, admin_user).call
    end

    def initialize(template, phone, variables, sender_number = nil, admin_user = nil)
      @template = template
      @phone = phone.to_s
      @variables = variables.to_h
      @sender_number = sender_number || WhatsappSenderNumber.default_for_campaign
      @admin_user = admin_user
    end

    def call
      return { ok: false, error: "Informe um telefone para teste." } if normalized_phone.blank?
      return { ok: false, error: "Número de envio WhatsApp não está configurado." } unless sender_number&.messaging_ready?

      components = template_components
      outbound = create_pending_outbound!
      response = Whatsapp::CloudClient.new(sender_number).send_template(
        to: normalized_phone,
        name: template.name,
        language: template.language.presence || "pt_BR",
        components: components
      )

      if response[:ok]
        outbound.update!(
          status: "sent",
          wa_message_id: response[:message_id],
          sent_at: Time.current,
          error_message: nil
        )
        conversation.touch_last_message!(outbound)

        {
          ok: true,
          message_id: response[:message_id],
          whatsapp_message_id: outbound.id,
          delivery_status: "sent",
          delivery_hint: "A Meta aceitou o teste. A entrega no aparelho depende do webhook de status: enviado, entregue, lido ou falhou."
        }
      else
        outbound.update!(status: "failed", error_message: response[:error].to_s.truncate(250))
        conversation.touch_last_message!(outbound)

        {
          ok: false,
          error: response[:error],
          error_hint: error_hint(response),
          meta_error: response[:meta_error]
        }.compact
      end
    rescue ArgumentError => e
      { ok: false, error: e.message }
    end

    private

    attr_reader :template, :phone, :variables, :sender_number, :admin_user

    def normalized_phone
      @normalized_phone ||= begin
        digits = phone.gsub(/\D/, "")
        return "" if digits.blank?

        digits.length <= 11 ? "55#{digits}" : digits
      end
    end

    def template_components
      values = Whatsapp::CampaignTemplatePreview.call(template: template, variables: variables).values
      variables_by_index = values.each_with_index.to_h { |value, index| [(index + 1).to_s, value] }
      result = Whatsapp::TemplateMessageComponents.call(template: template, variables: variables_by_index)
      raise ArgumentError, result.error unless result.ok?

      result.components
    end

    def create_pending_outbound!
      conversation.messages.create!(
        admin_user: admin_user,
        direction: "outbound",
        msg_type: "template",
        template_name: template.name,
        body: preview_body,
        status: "pending"
      ).tap { |message| conversation.touch_last_message!(message) }
    end

    def conversation
      @conversation ||= begin
        record = WhatsappConversation.find_or_initialize_by(contact_phone: normalized_phone)
        record.contact_name ||= "Teste WhatsApp #{normalized_phone}"
        record.status = "open"
        record.save!
        record
      end
    end

    def preview_body
      @preview_body ||= Whatsapp::CampaignTemplatePreview.call(template: template, variables: variables).body
    end

    def error_hint(response)
      code = response.dig(:meta_error, :code).to_s
      message = [response[:error], response.dig(:meta_error, :type)].compact.join(" ")

      if code == "132012" || message.match?(/parameter format/i)
        "O formato enviado não corresponde ao template aprovado na Meta. Revise se o modelo selecionado exige cabeçalho com mídia, variáveis no corpo/cabeçalho ou botão com URL dinâmica; o teste precisa preencher exatamente esses componentes."
      end
    end
  end
end
