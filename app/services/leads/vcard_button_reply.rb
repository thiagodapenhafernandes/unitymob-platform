module Leads
  # Toque no botão "Salvar contato" do aviso de distribuição (template v2):
  # localiza a notificação de origem pelo contexto (wamid), valida corretor +
  # toggle da conta e responde com o cartão de contato nativo. Como no link
  # seguro, o gesto vale como atendimento (e reivindica no bolsão).
  # Retorna true quando tratado (o inbound não segue o fluxo de cliente).
  class VcardButtonReply
    BUTTON_TITLE = "Salvar contato".freeze

    def self.call(tenant:, msg:)
      new(tenant, msg).call
    end

    def initialize(tenant, msg)
      @tenant = tenant
      @msg = msg
    end

    def call
      return false unless button_tap?
      activity = origin_notification
      return false if activity.nil?

      broker = @tenant.admin_users.find_by(id: activity.metadata["admin_user_id"])
      return false if broker.nil? || !from_broker?(broker)
      return false unless LeadSetting.instance(tenant: @tenant).vcard_enabled?

      lead = activity.lead
      return true if already_sent?(lead)
      return true unless ensure_attendance!(lead, broker)

      send_card!(lead, broker)
      true
    end

    private

    def button_tap?
      return false unless @msg["type"].to_s == "interactive"

      @msg.dig("interactive", "button_reply", "title").to_s.strip.casecmp?(BUTTON_TITLE)
    end

    def origin_notification
      context_id = @msg.dig("context", "id").presence
      return nil if context_id.blank?

      LeadActivity.joins(:lead)
                  .where(leads: { tenant_id: @tenant.id }, kind: "notification_sent")
                  .where("lead_activities.metadata->>'channel' = 'whatsapp'")
                  .where("lead_activities.metadata->>'message_id' = ?", context_id)
                  .order(created_at: :desc).first
    end

    def from_broker?(broker)
      broker_digits = comparable_digits(broker.phone)
      from_digits = comparable_digits(@msg["from"])
      broker_digits.present? && broker_digits == from_digits
    end

    # Compara sem DDI: corretor pode estar sem 55 e a Meta sempre manda com.
    def comparable_digits(phone)
      digits = Phones::Normalizer.call(phone).to_s
      digits = digits.delete_prefix("55") if digits.length > 11 && digits.start_with?("55")
      digits.presence
    end

    def already_sent?(lead)
      lead.activities.where(kind: "vcard_card_sent")
          .where("metadata->>'reply_wamid' = ?", @msg["id"]).exists?
    end

    # Espelha o link seguro: sem dono reivindica (leva quem tocou primeiro),
    # com outro dono avisa, aguardando aceite vira atendimento.
    def ensure_attendance!(lead, broker)
      if lead.admin_user_id.nil?
        return claim_for!(lead, broker)
      elsif lead.admin_user_id != broker.id
        send_taken_notice!(lead, broker)
        return false
      elsif Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)
        accepted = false
        lead.with_lock do
          accepted = lead.admin_user_id == broker.id &&
            Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance) &&
            lead.update(status: Lead.status_value(:em_atendimento))
        end
        lead.activities.create(kind: "accepted", metadata: { by: broker.name, via: "whatsapp" }.compact) if accepted
      end
      true
    end

    def claim_for!(lead, broker)
      claimable = [Lead.status_value(:novo), Lead.status_value(:em_atendimento), Lead.status_value(:waiting_acceptance)].compact
      if Lead.claim_unassigned!(lead.id, broker.id, statuses: claimable)
        lead.reload
        lead.distribution_rule&.mark_agent_served!(broker.id)
        lead.activities.create(kind: "accepted", metadata: {
          by: broker.name, admin_user_id: broker.id, via: "whatsapp",
          shark_tank: (true if lead.distribution_rule&.pool_mode?)
        }.compact)
        true
      else
        send_taken_notice!(lead, broker)
        false
      end
    end

    def send_taken_notice!(lead, broker)
      owner = lead.reload.admin_user&.name.presence || "outro corretor"
      send_text!(broker, "Este lead já foi assumido por #{owner}.")
    end

    def send_card!(lead, broker)
      sender = Notifications::TransportResolver.whatsapp(@tenant)&.sender
      unless sender
        Rails.logger.warn("[VcardButtonReply] sem transporte WhatsApp (tenant #{@tenant.id})")
        return
      end

      result = Whatsapp::CloudClient.new(sender).send_contacts(
        to: Phones::Normalizer.call(broker.phone),
        contacts: [Leads::Vcard.card(lead)],
        context_message_id: @msg["id"]
      )
      LeadActivity.log!(lead: lead, kind: "vcard_card_sent", metadata: {
        by: broker.name, admin_user_id: broker.id,
        reply_wamid: @msg["id"], card_message_id: result[:message_id]
      }.compact)
    end

    def send_text!(broker, text)
      sender = Notifications::TransportResolver.whatsapp(@tenant)&.sender
      return unless sender

      Whatsapp::CloudClient.new(sender).send_text(to: Phones::Normalizer.call(broker.phone), body: text)
    end
  end
end
