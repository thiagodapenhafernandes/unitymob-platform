class DistributionRuleAgent < ApplicationRecord
  include TenantScoped

  belongs_to :distribution_rule
  belongs_to :admin_user

  validates :weight, numericality: { greater_than_or_equal_to: 1 }
  validate :admin_user_must_be_eligible_for_rule

  before_validation do
    self.allowed_meta_campaign_ids = Array(allowed_meta_campaign_ids).map { |id| id.to_s.strip }.compact_blank.uniq
  end
  validate :campaigns_belong_to_rule_tenant

  def self.campaign_id_for(entry)
    return "" unless entry
    info = entry.other_information.to_h
    context = info["distribution_entry"]
    (context.is_a?(Hash) && context.key?("meta_campaign_id") ? context["meta_campaign_id"] : info["meta_campaign_id"]).to_s
  end

  # Vazio mantém a participação atual em todas as origens; restrito exige ID identificado.
  def allows_campaign?(entry)
    return false if entry && entry.tenant_id != distribution_rule.tenant_id

    allowed_meta_campaign_ids.empty? || allowed_meta_campaign_ids.include?(self.class.campaign_id_for(entry))
  end

  before_save :assign_tenant_from_context
  before_create :set_initial_position

  private

  def campaigns_belong_to_rule_tenant
    return if allowed_meta_campaign_ids.empty? || distribution_rule.blank?
    return unless will_save_change_to_allowed_meta_campaign_ids?

    known_ids = MetaCampaignInsight.where(tenant_id: distribution_rule.tenant_id).distinct.pluck(:campaign_id)
    if (allowed_meta_campaign_ids - known_ids).any?
      errors.add(:allowed_meta_campaign_ids, "deve conter somente campanhas Meta sincronizadas desta conta")
    end
  end

  def admin_user_must_be_eligible_for_rule
    return if distribution_rule.blank? || admin_user.blank?

    unless admin_user.tenant_id == distribution_rule.tenant_id
      errors.add(:admin_user, "deve pertencer ao mesmo Tenant da regra")
      return
    end

    return if distribution_rule.eligible_distribution_agent?(admin_user)

    errors.add(:admin_user, "deve ser usuário ativo da conta com perfil vertical")
  end

  def set_initial_position
    return if position.present? # respeita a ordem definida no form (arraste da fila)

    max_pos = distribution_rule.distribution_rule_agents.maximum(:position) || 0
    self.position = max_pos + 1
  end
end
