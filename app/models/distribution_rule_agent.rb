class DistributionRuleAgent < ApplicationRecord
  include TenantScoped

  belongs_to :distribution_rule
  belongs_to :admin_user

  validates :weight, numericality: { greater_than_or_equal_to: 1 }
  validate :admin_user_must_be_eligible_for_rule

  before_save :assign_tenant_from_context
  before_create :set_initial_position

  private

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
