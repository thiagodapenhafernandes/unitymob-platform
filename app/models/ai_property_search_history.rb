class AiPropertySearchHistory < ApplicationRecord
  belongs_to :tenant
  belongs_to :admin_user
  belongs_to :selected_habitation, class_name: "Habitation", optional: true

  validates :status, presence: true, inclusion: { in: %w[completed clarification_required failed] }
  validates :result_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :tenant_consistency

  private

  def tenant_consistency
    errors.add(:admin_user, "não pertence à conta") if admin_user && admin_user.tenant_id != tenant_id
    if selected_habitation && selected_habitation.tenant_id != tenant_id
      errors.add(:selected_habitation, "não pertence à conta")
    end
  end
end
