class C2sLeadReactivation < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending reactivating reactivated redistributing completed failed uncertain].freeze

  belongs_to :lead
  belongs_to :whatsapp_campaign_message, optional: true
  belongs_to :distribution_rule, optional: true
  belongs_to :external_lead_integration, optional: true

  validates :external_lead_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :whatsapp_campaign_message, :distribution_rule, :external_lead_integration, presence: true, on: :create
  validate :associations_belong_to_tenant

  after_create_commit :enqueue_reactivation

  def self.request!(lead:, campaign_message:, distribution_rule:)
    raise ArgumentError, "Reativação exige um lead existente" unless lead&.persisted?

    integration = lead.tenant.external_lead_integration
    unless campaign_message&.tenant_id == lead.tenant_id && campaign_message.replied? &&
        (campaign_message.lead_id == lead.id || campaign_message.whatsapp_campaign_recipient&.lead_id == lead.id) &&
        distribution_rule.tenant_id == lead.tenant_id && distribution_rule.active? &&
        distribution_rule.source_whatsapp_campaign? && distribution_rule.destination_c2s? && positive_reply_for?(campaign_message, distribution_rule)
      raise ArgumentError, "Reativação exige resposta da campanha e fila C2S da mesma conta"
    end
    external_id = lead.c2s_existing_id_for(integration)
    raise ArgumentError, "Lead sem vínculo seguro com o cadastro existente no C2S" if external_id.blank?

    lead.tenant.c2s_lead_reactivations.create_or_find_by!(whatsapp_campaign_message: campaign_message) do |operation|
      operation.assign_attributes(lead: lead, distribution_rule: distribution_rule,
        external_lead_integration: integration, external_lead_id: external_id)
    end
  end

  def self.positive_reply_for?(message, rule)
    return false unless message&.persisted? && message.replied? && rule
    decision = message.whatsapp_campaign.response_decision_for(
      button_text: message.reply_button_text.presence || message.reply_body,
      button_payload: message.reply_button_payload
    ).with_indifferent_access
    decision[:action] == "generate_lead" && decision[:distribution_rule_id].to_s == rule.id.to_s
  end

  private

  def enqueue_reactivation
    job = ExternalLeadMigration::ReactivateLeadJob.perform_later(id, tenant_id: tenant_id)
    raise ActiveJob::EnqueueError, "Agendamento recusado" if job == false
    LeadActivity.log!(lead: lead, kind: "c2s_reactivation_queued", metadata: {
      reactivation_id: id, whatsapp_campaign_message_id: whatsapp_campaign_message_id, rule_id: distribution_rule_id
    })
  rescue StandardError => error
    reason = "Não foi possível agendar a reativação: #{error.class.name}"
    update!(status: "failed", error_message: reason)
    LeadActivity.log!(lead: lead, kind: "c2s_reactivation_failed", metadata: { reactivation_id: id, rule_id: distribution_rule_id, reason: reason })
    raise
  end

  def associations_belong_to_tenant
    [lead, whatsapp_campaign_message, distribution_rule, external_lead_integration].compact.each do |record|
      errors.add(:base, "Os vínculos da reativação devem pertencer à mesma conta") unless record.tenant_id == tenant_id
    end
  end
end
