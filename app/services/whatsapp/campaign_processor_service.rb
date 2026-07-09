require "set"

module Whatsapp
  class CampaignProcessorService
    def self.call(campaign)
      new(campaign).call
    end

    def initialize(campaign)
      @campaign = campaign
    end

    def call
      validate_campaign!
      audience = Whatsapp::CampaignAudienceResolver.call(campaign, materialize: true)
      raise ArgumentError, audience.errors.to_sentence if audience.errors.present?

      recipients = audience.recipients_with_phone
      campaign.update!(requested_recipients: collection_count(recipients))

      if campaign.requested_recipients.zero?
        campaign.fail!("Nenhum destinatário com telefone foi encontrado para a audiência selecionada.")
        return
      end

      create_messages!(recipients)
      campaign.refresh_counters!
      campaign.emit_event!("whatsapp_campaign_started", payload: campaign.metrics_payload)
      Whatsapp::BulkSendJob.perform_later(campaign.id, tenant_id: campaign.tenant_id)
    rescue => e
      Rails.logger.error("[whatsapp campaign] process failed campaign=#{campaign&.id}: #{e.class} - #{e.message}")
      campaign&.fail!(e.message)
    end

    private

    attr_reader :campaign

    def validate_campaign!
      raise ArgumentError, "Campanha não está em processamento." unless campaign.processing?
      raise ArgumentError, "Número de envio WhatsApp não está configurado." unless campaign.sender_number&.messaging_ready?
      raise ArgumentError, "Modelo WhatsApp precisa estar aprovado." unless campaign.whatsapp_template.approved?
    end

    def create_messages!(recipients)
      rows = []
      now = Time.current

      # Lock na campanha torna o check-then-insert atômico: um segundo processor
      # concorrente relê existing_ids já com as linhas do primeiro e não duplica
      # o disparo (o start! atômico impede o caso comum; isto fecha o residual).
      campaign.with_lock do
        each_new_recipient(recipients) do |recipient|
          phone = Phones::Normalizer.call(recipient.display_phone).to_s
          next if phone.blank?

          rows << {
            tenant_id: campaign.tenant_id,
            whatsapp_campaign_id: campaign.id,
            whatsapp_campaign_recipient_id: recipient.id,
            lead_id: recipient.respond_to?(:lead_id) ? recipient.lead_id : recipient.id,
            phone_number: phone,
            status: "pending",
            template_variables: template_variables_for(recipient),
            created_at: now,
            updated_at: now
          }
        end

        WhatsappCampaignMessage.insert_all(rows) if rows.any?
      end
    end

    def each_new_recipient(recipients, &block)
      existing_ids = campaign.campaign_messages.pluck(:whatsapp_campaign_recipient_id)
      if recipients.respond_to?(:where)
        recipients.where.not(id: existing_ids).find_each(&block)
      else
        existing_lookup = existing_ids.compact.to_set
        recipients.each { |recipient| block.call(recipient) unless existing_lookup.include?(recipient.id) }
      end
    end

    def collection_count(recipients)
      recipients.respond_to?(:count) ? recipients.count : recipients.size
    end

    def template_variables_for(recipient)
      mapping = campaign.template_variables.to_h
      return default_template_variables(recipient) if mapping.blank?

      mapping.transform_values { |value| render_value(value, recipient) }
    end

    def default_template_variables(recipient)
      count = campaign.whatsapp_template.variable_count
      values = {
        "1" => recipient.display_name,
        "2" => recipient.display_phone,
        "3" => recipient.origin,
        "4" => recipient.admin_user&.name
      }
      count.positive? ? values.slice(*Array(1..count).map(&:to_s)) : {}
    end

    def render_value(value, recipient)
      lead = recipient.respond_to?(:lead) ? recipient.lead : recipient
      value.to_s
           .gsub("{{nome}}", recipient.display_name.to_s)
           .gsub("{{telefone}}", recipient.display_phone.to_s)
           .gsub("{{email}}", recipient.display_email.to_s)
           .gsub("{{origem}}", recipient.origin.to_s)
           .gsub("{{status}}", recipient.status.to_s)
           .gsub("{{tags}}", recipient.tag_list.join(", "))
           .gsub("{{produto}}", lead&.respond_to?(:product) ? lead.product.to_s : "")
           .gsub("{{empresa}}", campaign.sender_number&.verified_name.to_s.presence || campaign.sender_number&.label.to_s)
           .gsub("{{observacoes}}", lead&.respond_to?(:notes) ? lead.notes.to_s : "")
           .gsub("{{corretor}}", recipient.admin_user&.name.to_s)
           .gsub("{{corretor_telefone}}", recipient.admin_user&.try(:phone).to_s.presence || recipient.admin_user&.try(:telefone).to_s)
           .gsub("{{corretor_email}}", recipient.admin_user&.notification_email.to_s)
    end

  end
end
