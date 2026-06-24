class DistributionRuleAgent < ApplicationRecord
  belongs_to :distribution_rule
  belongs_to :admin_user

  validates :weight, numericality: { greater_than_or_equal_to: 1 }

  before_create :set_initial_position

  private

  def set_initial_position
    return if position.present? # respeita a ordem definida no form (arraste da fila)

    max_pos = distribution_rule.distribution_rule_agents.maximum(:position) || 0
    self.position = max_pos + 1
  end
end
