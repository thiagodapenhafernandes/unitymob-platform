# Shared rule for activities linked to a lead; personal activities remain valid.
module LeadOwnerRequired
  extend ActiveSupport::Concern

  included do
    validate :linked_lead_must_have_owner
  end

  def lead_owner_missing?
    lead.present? && lead.admin_user_id.blank?
  end

  private

  def linked_lead_must_have_owner
    return unless lead_owner_missing?
    return if status.in?(%w[concluida cancelada realizado cancelado]) && persisted?

    errors.add(:lead, "precisa ter um corretor atribuído antes de criar ou agendar uma atividade")
  end
end
