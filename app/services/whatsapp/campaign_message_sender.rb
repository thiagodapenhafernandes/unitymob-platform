module Whatsapp
  class CampaignMessageSender
    def self.call(campaign_message)
      new(campaign_message).call
    end

    def initialize(campaign_message)
      @campaign_message = campaign_message
      @campaign = campaign_message.whatsapp_campaign
      @lead = campaign_message.lead
      @recipient = campaign_message.whatsapp_campaign_recipient
    end

    def call
      if unsubscribed_contact?
        campaign_message.mark_cancelled!("Contato descadastrado para campanhas deste número.")
        return
      end

      campaign_message.queue!
      conversation = find_or_create_conversation!
      template = campaign.whatsapp_template
      body = template.render_body(template_values)
      outbound = conversation.messages.create!(
        direction: "outbound",
        msg_type: "template",
        template_name: template.name,
        body: body,
        status: "pending"
      )
      conversation.touch_last_message!(outbound)

      result = client.send_template(
        to: campaign_message.phone_number,
        name: template.name,
        language: template.language.presence || "pt_BR",
        components: template_components
      )

      if result[:ok]
        outbound.update!(status: "sent", wa_message_id: result[:message_id], sent_at: Time.current, error_message: nil)
        campaign_message.mark_sent!(message_id: result[:message_id], whatsapp_message: outbound)
        log_outbound_activity(outbound)
      else
        outbound.update!(status: "failed", error_message: result[:error].to_s.truncate(250))
        campaign_message.mark_failed!(result[:error])
        schedule_retry_if_needed
        pause_campaign_for_template_error!(result[:error])
      end
    rescue => e
      campaign_message.mark_failed!(e.message)
      schedule_retry_if_needed
      Rails.logger.warn("[whatsapp campaign sender] message=#{campaign_message&.id} #{e.class}: #{e.message}")
    end

    private

    attr_reader :campaign_message, :campaign, :lead, :recipient

    def unsubscribed_contact?
      WhatsappCampaignUnsubscribe.active_for?(
        sender_number: campaign.sender_number,
        phone: campaign_message.phone_number
      )
    end

    def pause_campaign_for_template_error!(error)
      text = error.to_s
      return unless text.include?("132015") || text.downcase.include?("template is temporarily unavailable")

      campaign.pause_for_template_error!("Template indisponível na Meta: #{text}")
    end

    def schedule_retry_if_needed
      campaign_message.reload
      return if campaign_message.next_retry_at.blank?
      return if campaign_message.retry_count.to_i >= 3

      Whatsapp::CampaignMessageRetryJob
        .set(wait_until: campaign_message.next_retry_at)
        .perform_later(campaign_message.id, tenant_id: campaign_message.tenant_id)
    end

    def find_or_create_conversation!
      conversation = campaign.tenant.whatsapp_conversations.find_or_initialize_by(contact_phone: campaign_message.phone_number)
      conversation.lead ||= lead if lead
      conversation.contact_name ||= recipient&.display_name || lead&.display_name || campaign_message.phone_number
      conversation.status = "open"
      conversation.save!
      conversation
    end

    def log_outbound_activity(outbound)
      return unless lead

      LeadActivity.log!(
        lead: lead,
        kind: "whatsapp_out",
        metadata: { body: outbound.preview, by: "Disparo WhatsApp", whatsapp_campaign_id: campaign.id }
      )
    end

    def template_values
      vars = campaign_message.template_variables.to_h
      keys = vars.keys.sort_by { |key| key.to_s.to_i }
      keys.map { |key| vars[key].to_s }
    end

    def template_components
      vars = campaign_message.template_variables.to_h
      result = Whatsapp::TemplateMessageComponents.call(template: campaign.whatsapp_template, variables: vars, client: client)
      raise ArgumentError, result.error unless result.ok?

      result.components
    end

    def client
      @client ||= Whatsapp::CloudClient.new(campaign.sender_number)
    end
  end
end
